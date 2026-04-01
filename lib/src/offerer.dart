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

  Future<Offer> offer(
    OfferConfig offerConfig,
    Session session,
    String requestID,
  ) async {
    final config = {
      "iceServers": offerConfig.iceServers,
    };

    final peerConnection = await createPeerConnection(config);

    peerConnection.onIceCandidate = (candidate) async {
      final answerData = jsonEncode(candidate.toMap());

      await session.publish(offerConfig.topicAnswererOnCandidate, args: [requestID, answerData]);
    };

    connection = peerConnection;

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
}
