import "dart:async";
import "dart:convert";

import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:xconn/xconn.dart";
import "package:xconn_webrtc_dart/xconn_webrtc_dart.dart";

class WebRTCConnectionFailedException implements Exception {
  WebRTCConnectionFailedException(this.state);

  final RTCPeerConnectionState state;

  @override
  String toString() {
    return "WebRTC connection failed before data channel opened: $state";
  }
}

class Offerer {
  RTCPeerConnection? connection;

  void Function()? onDisconnect;

  final Completer<RTCDataChannel> _readyCompleter = Completer<RTCDataChannel>();
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];
  bool _remoteDescriptionSet = false;
  Session? _trickleSession;
  String? _trickleTopic;
  String? _trickleRequestID;
  bool _channelClosed = false;
  bool _connected = false;
  bool _disconnectFired = false;

  final StreamController<RTCDataChannel> _incomingChannelsController = StreamController<RTCDataChannel>();

  // Raw (non-WAMP) data channels the remote peer opens on this connection,
  // e.g. deskconnd's "file-stream" channel: it opens this itself rather than
  // waiting for the client to, since some clients (observed on Android)
  // can't reliably create additional data channels once already connected.
  Stream<RTCDataChannel> get incomingChannels => _incomingChannelsController.stream;

  final Map<String, Completer<RTCDataChannel>> _extraChannelCompleters = {};

  // Raw (non-WAMP) data channels created up front, alongside the main "data"
  // channel, before the initial offer — so they're part of the same DCEP
  // handshake instead of being opened after the connection is already
  // established (unreliable on some clients, observed on Android). Populated
  // for every label in OfferConfig.additionalChannels; resolves once each
  // channel actually reaches the open state.
  Future<RTCDataChannel> extraChannel(String label) {
    return _extraChannelCompleters.putIfAbsent(label, Completer<RTCDataChannel>.new).future;
  }

  Future<Offer> offer(
    OfferConfig offerConfig,
  ) async {
    // Loopback can never reach a remote peer; gathering/checking it just delays ICE gathering completion.
    await WebRTC.initialize(
      options: {
        "networkIgnoreMask": [AdapterType.adapterTypeLoopback.name],
      },
    );

    final config = {
      "iceServers": offerConfig.iceServers,
      "iceCandidatePoolSize": 10,
    };

    final peerConnection = await createPeerConnection(config);

    connection = peerConnection;

    peerConnection.onDataChannel = (channel) {
      if (!_incomingChannelsController.isClosed) {
        _incomingChannelsController.add(channel);
      }
    };

    final options = RTCDataChannelInit()
      ..ordered = offerConfig.ordered
      ..protocol = offerConfig.protocol
      ..id = offerConfig.id;

    final dc = await peerConnection.createDataChannel("data", options);

    dc.onDataChannelState = (state) {
      print("Data Channel State has changed: $state");

      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _connected = true;
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.complete(dc);
        }
      } else if (state == RTCDataChannelState.RTCDataChannelClosing ||
          state == RTCDataChannelState.RTCDataChannelClosed) {
        _failReady(
          WebRTCConnectionFailedException(
            peerConnection.connectionState ?? RTCPeerConnectionState.RTCPeerConnectionStateClosed,
          ),
        );
      }
    };

    peerConnection.onConnectionState = (state) {
      print("Peer Connection State has changed: $state");

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _failReady(WebRTCConnectionFailedException(state));
        _closeChannel(dc);
        unawaited(_incomingChannelsController.close());
        for (final completer in _extraChannelCompleters.values) {
          if (!completer.isCompleted) {
            completer.completeError(WebRTCConnectionFailedException(state));
          }
        }

        if (_connected && !_disconnectFired) {
          _disconnectFired = true;
          onDisconnect?.call();
        }
      }
    };

    for (final label in offerConfig.additionalChannels) {
      final extraOptions = RTCDataChannelInit()..ordered = true;
      final extraChannel = await peerConnection.createDataChannel(label, extraOptions);
      final completer = _extraChannelCompleters.putIfAbsent(label, Completer<RTCDataChannel>.new);
      extraChannel.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          if (!completer.isCompleted) {
            completer.complete(extraChannel);
          }
        } else if (state == RTCDataChannelState.RTCDataChannelClosing ||
            state == RTCDataChannelState.RTCDataChannelClosed) {
          if (!completer.isCompleted) {
            completer.completeError(WebRTCPeerClosedException("extra data channel '$label' closed before opening"));
          }
        }
      };
    }

    // Collect host ICE candidates for up to 100ms and bundle them with the
    // offer.
    const trickleAfter = Duration(milliseconds: 100);
    final deadline = DateTime.now().add(trickleAfter);
    final List<RTCIceCandidate> initialCandidates = [];
    final trickleReady = Completer<void>();

    peerConnection.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;

      if (!trickleReady.isCompleted && DateTime.now().isBefore(deadline)) {
        initialCandidates.add(candidate);
        if (!candidate.candidate!.contains('typ host')) {
          trickleReady.complete();
        }
      } else {
        _onIceCandidate(candidate);
      }
    };

    final sdpOffer = await peerConnection.createOffer();
    await peerConnection.setLocalDescription(sdpOffer);

    await Future.any([trickleReady.future, Future.delayed(trickleAfter)]);

    // Switch to normal trickle handler for all candidates from here on.
    peerConnection.onIceCandidate = _onIceCandidate;

    return Offer(description: sdpOffer, candidates: initialCandidates);
  }

  void startICETrickle(Session session, String topic, String requestID) {
    _trickleSession = session;
    _trickleTopic = topic;
    _trickleRequestID = requestID;

    final pendingCandidates = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    pendingCandidates.forEach(_publishCandidate);
  }

  Future<void> handleAnswer(Answer answer) async {
    await connection!.setRemoteDescription(answer.description);
    _remoteDescriptionSet = true;

    for (final candidate in answer.candidates) {
      await connection!.addCandidate(candidate);
    }

    // Flush remote candidates that arrived via trickle before setRemoteDescription.
    for (final candidate in _pendingRemoteCandidates) {
      await connection!.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> addICECandidate(RTCIceCandidate candidate) async {
    if (!_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }

    await connection!.addCandidate(candidate);
  }

  Future<RTCDataChannel> waitReady() {
    return _readyCompleter.future;
  }

  void _failReady(Object error) {
    if (_readyCompleter.isCompleted) {
      return;
    }

    _readyCompleter.completeError(error);
  }

  void _closeChannel(RTCDataChannel dc) {
    if (_channelClosed) {
      return;
    }
    _channelClosed = true;
    unawaited(dc.close());
  }

  void _onIceCandidate(RTCIceCandidate candidate) {
    if (_trickleSession == null || _trickleTopic == null || _trickleRequestID == null) {
      _pendingCandidates.add(candidate);
      return;
    }

    _publishCandidate(candidate);
  }

  void _publishCandidate(RTCIceCandidate candidate) {
    final session = _trickleSession;
    final topic = _trickleTopic;
    final requestID = _trickleRequestID;
    if (session == null || topic == null || requestID == null) {
      return;
    }

    final answerData = jsonEncode(candidate.toMap());
    unawaited(session.publish(topic, args: [requestID, answerData]));
  }
}
