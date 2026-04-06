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
  late RTCPeerConnection? connection;
  final Completer<RTCDataChannel> _readyCompleter = Completer<RTCDataChannel>();
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];
  Session? _trickleSession;
  String? _trickleTopic;
  String? _trickleRequestID;

  Future<Offer> offer(
    OfferConfig offerConfig,
  ) async {
    final config = {
      "iceServers": offerConfig.iceServers,
    };

    final peerConnection = await createPeerConnection(config);

    connection = peerConnection;
    peerConnection.onIceCandidate = _onIceCandidate;

    final options = RTCDataChannelInit()
      ..ordered = offerConfig.ordered
      ..protocol = offerConfig.protocol
      ..id = offerConfig.id;

    final dc = await peerConnection.createDataChannel("data", options);

    dc.onDataChannelState = (state) {
      print("Data Channel State has changed: $state");

      if (state == RTCDataChannelState.RTCDataChannelOpen) {
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
      }
    };

    final offer = await peerConnection.createOffer();

    await peerConnection.setLocalDescription(offer);

    return Offer(description: offer, candidates: []);
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

    for (final candidate in answer.candidates) {
      await connection!.addCandidate(candidate);
    }
  }

  Future<void> addICECandidate(RTCIceCandidate candidate) async {
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
