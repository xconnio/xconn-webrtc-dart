import "dart:convert";

import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:wampproto/auth.dart";
import "package:xconn/xconn.dart";
import "package:xconn_webrtc_dart/src/helpers.dart";
import "package:xconn_webrtc_dart/xconn_webrtc_dart.dart";

class ClientConfig {
  ClientConfig({
    required this.realm,
    required this.procedureWebRTCOffer,
    required this.topicAnswererOnCandidate,
    required this.topicOffererOnCandidate,
    required this.session,
    this.iceServers,
    this.serializer,
    this.authenticator,
  });

  String realm;
  String procedureWebRTCOffer;
  String topicAnswererOnCandidate;
  String topicOffererOnCandidate;
  List<Map<String, dynamic>>? iceServers;

  Serializer? serializer;
  IClientAuthenticator? authenticator;
  Session session;

  void validate() {
    if (realm.isEmpty) {
      throw Exception("realm must not be empty");
    }

    if (procedureWebRTCOffer.isEmpty) {
      throw Exception("ProcedureWebRTCOffer must not be empty");
    }

    if (topicAnswererOnCandidate.isEmpty) {
      throw Exception("TopicAnswererOnCandidate must not be empty");
    }

    if (topicOffererOnCandidate.isEmpty) {
      throw Exception("TopicOffererOnCandidate must not be empty");
    }

    serializer ??= CBORSerializer();
    authenticator ??= AnonymousAuthenticator("");
    iceServers ??= [];
  }
}

Future<WebRTCSession> _connectWebRTC(ClientConfig config) async {
  config.validate();

  final offerer = Offerer();

  final offerConfig = OfferConfig(
    protocol: getSubProtocol(config.serializer!),
    iceServers: config.iceServers!,
    ordered: true,
    id: 0,
    topicAnswererOnCandidate: config.topicAnswererOnCandidate,
  );

  await config.session.subscribe(config.topicOffererOnCandidate, (Event event) async {
    if (event.args.length < 2) {
      print("invalid arguments length");
      return;
    }

    final candidateJSON = event.args[1];

    final candidateMap = jsonDecode(candidateJSON);

    final candidate = RTCIceCandidate(
      candidateMap["candidate"],
      candidateMap["sdpMid"],
      candidateMap["sdpMLineIndex"],
    );

    try {
      await offerer.addICECandidate(candidate);
    } catch (e) {
      print(e);
    }
  });

  final offer = await offerer.offer(offerConfig);

  final offerJSON = jsonEncode(offer);

  final callResponse = await config.session.call(config.procedureWebRTCOffer, args: [offerJSON]);

  final offerResponseText = callResponse.args[0] as String;

  final offerResponseMap = jsonDecode(offerResponseText) as Map<String, dynamic>;
  final offerResponse = OfferResponse.fromJson(offerResponseMap);

  if (offerResponse.requestID.isEmpty) {
    throw Exception("offer response request ID must not be empty");
  }

  offerer.startICETrickle(config.session, offerConfig.topicAnswererOnCandidate, offerResponse.requestID);

  await offerer.handleAnswer(offerResponse.answer);

  final channel = await offerer.waitReady();

  return WebRTCSession(
    channel: channel,
    connection: offerer.connection!,
  );
}

Future<WebRTCSession> connectWebRTC(ClientConfig config) async {
  final webRTCSession = await _connectWebRTC(config);

  final peer = WebRTCPeer(webRTCSession.channel);

  await joinPeer(peer, config.realm, config.serializer!, config.authenticator!);

  return WebRTCSession(
    channel: webRTCSession.channel,
    connection: webRTCSession.connection,
  );
}

Future<Session> connectWAMP(ClientConfig config) async {
  final webRTCConnection = await _connectWebRTC(config);

  final peer = WebRTCPeer(webRTCConnection.channel);

  final base = await joinPeer(
    peer,
    config.realm,
    config.serializer!,
    config.authenticator!,
  );

  final wampSession = Session(base);

  return wampSession;
}
