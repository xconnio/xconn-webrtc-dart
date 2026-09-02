import "package:flutter_webrtc/flutter_webrtc.dart";

class Answer {
  Answer({
    required this.candidates,
    required this.description,
  });

  factory Answer.fromJson(Map<String, dynamic> json) {
    return Answer(
      candidates: ((json["candidates"] as List?) ?? const [])
          .map((c) => RTCIceCandidate(c["candidate"], c["sdpMid"], c["sdpMLineIndex"]))
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

class OfferResponse {
  OfferResponse({
    required this.requestID,
    required this.answer,
  });

  factory OfferResponse.fromJson(Map<String, dynamic> json) {
    return OfferResponse(
      requestID: json["requestID"] as String,
      answer: Answer.fromJson(json["answer"] as Map<String, dynamic>),
    );
  }

  final String requestID;
  final Answer answer;

  Map<String, dynamic> toJson() {
    return {
      "requestID": requestID,
      "answer": answer.toJson(),
    };
  }
}

class OfferConfig {
  OfferConfig({
    required this.protocol,
    required this.iceServers,
    required this.ordered,
    required this.id,
    required this.topicAnswererOnCandidate,
    this.additionalChannels = const [],
  });

  final String protocol;
  final List<Map<String, dynamic>> iceServers;
  final bool ordered;
  final int id;
  final String topicAnswererOnCandidate;

  // Raw (non-WAMP) data channel labels to create alongside the main "data"
  // channel, before the offer is sent, so they're part of the initial DCEP
  // handshake instead of being opened later (unreliable on some clients,
  // observed on Android). See Offerer.extraChannel.
  final List<String> additionalChannels;
}

class WebRTCSession {
  WebRTCSession({
    required this.connection,
    required this.channel,
    Stream<RTCDataChannel>? incomingChannels,
    Future<RTCDataChannel> Function(String label)? extraChannel,
  })  : _incomingChannels = incomingChannels,
        _extraChannel = extraChannel;

  final RTCPeerConnection connection;
  final RTCDataChannel channel;
  final Stream<RTCDataChannel>? _incomingChannels;
  final Future<RTCDataChannel> Function(String label)? _extraChannel;

  // A raw (non-WAMP) data channel created up front alongside the main "data"
  // channel (see OfferConfig.additionalChannels / Offerer.extraChannel).
  // Resolves once it actually opens. Only available when this session was
  // built with extraChannel — throws on access otherwise.
  Future<RTCDataChannel> extraChannel(String label) {
    final resolver = _extraChannel;
    if (resolver == null) {
      throw StateError(
        "WebRTCSession.extraChannel is unavailable: this session was constructed "
        "without extraChannel",
      );
    }
    return resolver(label);
  }

  Future<RTCDataChannel> openChannel(
    String label,
    RTCDataChannelInit options,
  ) {
    return connection.createDataChannel(label, options);
  }

  // Raw (non-WAMP) data channels the remote peer opens on this connection.
  // Only available when this session was built with incomingChannels (see
  // Offerer.incomingChannels) — a session constructed without it throws on
  // access, since it has no way to receive channels the remote peer opens.
  Stream<RTCDataChannel> get onDataChannel {
    final channels = _incomingChannels;
    if (channels == null) {
      throw StateError(
        "WebRTCSession.onDataChannel is unavailable: this session was constructed "
        "without incomingChannels",
      );
    }
    return channels;
  }
}
