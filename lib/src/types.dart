import "package:flutter_webrtc/flutter_webrtc.dart";

class Answer {
  Answer({
    required this.candidates,
    required this.description,
  });

  factory Answer.fromJson(Map<String, dynamic> json) {
    return Answer(
      candidates: (json["candidates"] as List)
          .map((c) => RTCIceCandidate(
        c["candidate"],
        c["sdpMid"],
        c["sdpMLineIndex"],
      ))
          .toList(),
      description: RTCSessionDescription(
        json["description"]["sdp"],
        json["description"]["type"],
      ),
    );
  }

  final List<RTCIceCandidate> candidates;
  final RTCSessionDescription description;

  Map<String, dynamic> toJson() {
    return {
      "candidates": candidates.map((c) => c.toMap()).toList(),
      "description": description.toMap(),
    };
  }
}
typedef Offer = Answer;

class OfferConfig {
  OfferConfig({
    required this.protocol,
    required this.iceServers,
    required this.ordered,
    required this.id,
    required this.topicAnswererOnCandidate,
  });

  final String protocol;
  final List<Map<String, dynamic>> iceServers;
  final bool ordered;
  final int id;
  final String topicAnswererOnCandidate;
}

class WebRTCSession {
  WebRTCSession({
    required this.connection,
    required this.channel,
  });

  final RTCPeerConnection connection;
  final RTCDataChannel channel;

  Future<RTCDataChannel> openChannel(
    String label,
    RTCDataChannelInit options,
  ) {
    return connection.createDataChannel(label, options);
  }
}
