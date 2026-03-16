import "dart:async";
import "dart:convert";

import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:xconn/xconn.dart";
import "package:xconn_webrtc_dart/xconn_webrtc_dart.dart";

class Offerer {
  late RTCPeerConnection? connection;
  final StreamController<RTCDataChannel> _channelController = StreamController<RTCDataChannel>.broadcast();

  Stream<RTCDataChannel> get channel => _channelController.stream;

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
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _channelController.add(dc);
      }
    };

    peerConnection.onConnectionState = (state) {
      print("Peer Connection State has changed: $state");
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

  Stream<RTCDataChannel> waitReady() {
    return channel;
  }
}
