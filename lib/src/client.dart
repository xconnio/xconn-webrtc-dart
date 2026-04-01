import "dart:convert";

import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:uuid/uuid.dart";
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
    this.serializer,
    this.authenticator,
    this.session,
  });
  String realm;
  String procedureWebRTCOffer;
  String topicAnswererOnCandidate;
  String topicOffererOnCandidate;

  Serializer? serializer;
  IClientAuthenticator? authenticator;
  Session? session;

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

    serializer ??= JSONSerializer();
    authenticator ??= AnonymousAuthenticator("");

    if (session == null) {
      throw Exception("session must not be nil");
    }
  }
}

Future<WebRTCSession> _connectWebRTC(ClientConfig config) async {
  config.validate();

  final offerer = Offerer();

  final offerConfig = OfferConfig(
    protocol: getSubProtocol(config.serializer!),
    iceServers: [],
    ordered: true,
    id: 0,
    topicAnswererOnCandidate: config.topicAnswererOnCandidate,
  );

  await config.session!.subscribe(config.topicOffererOnCandidate, (Event event) async {
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

  final requestID = const Uuid().v4();

  final offer = await offerer.offer(
    offerConfig,
    config.session!,
    requestID,
  );

  final offerJSON = jsonEncode(offer);

  final callResponse = await config.session!.call(config.procedureWebRTCOffer, args: [requestID, offerJSON]);

  final answerText = callResponse.args[0];

  final answerMap = jsonDecode(answerText);

  final answer = Answer.fromJson(answerMap);

  await offerer.handleAnswer(answer);

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
