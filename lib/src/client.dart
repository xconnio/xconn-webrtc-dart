import "dart:async";
import "dart:convert";

import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:wampproto/auth.dart";
import "package:xconn/xconn.dart";
import "package:xconn_webrtc_dart/src/helpers.dart";
import "package:xconn_webrtc_dart/xconn_webrtc_dart.dart";

const _connectTimeout = Duration(seconds: 20);

class _PendingRemoteCandidate {
  _PendingRemoteCandidate(this.requestID, this.candidate);

  final String requestID;
  final RTCIceCandidate candidate;
}

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
    this.onDisconnect,
  });

  String realm;
  String procedureWebRTCOffer;
  String topicAnswererOnCandidate;
  String topicOffererOnCandidate;
  List<Map<String, dynamic>>? iceServers;

  Serializer? serializer;
  IClientAuthenticator? authenticator;
  Session session;

  // Called when the WebRTC connection is lost.
  void Function()? onDisconnect;

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

  final offerer = Offerer()..onDisconnect = config.onDisconnect;
  String requestID = "";
  final pendingCandidates = <_PendingRemoteCandidate>[];

  final offerConfig = OfferConfig(
    protocol: getSubProtocol(config.serializer!),
    iceServers: config.iceServers!,
    ordered: true,
    id: 0,
    topicAnswererOnCandidate: config.topicAnswererOnCandidate,
  );

  // Subscribe and create the offer concurrently.
  final offerFuture = offerer.offer(offerConfig);
  final subscription = await config.session.subscribe(config.topicOffererOnCandidate, (Event event) async {
    if (event.args.length < 2) {
      print("invalid arguments length");
      return;
    }

    final candidateRequestID = event.args[0] as String?;
    if (candidateRequestID == null) {
      return;
    }

    final candidateJSON = event.args[1];

    final candidateMap = jsonDecode(candidateJSON);

    final candidate = RTCIceCandidate(
      candidateMap["candidate"],
      candidateMap["sdpMid"],
      candidateMap["sdpMLineIndex"],
    );

    if (requestID.isEmpty) {
      pendingCandidates.add(_PendingRemoteCandidate(candidateRequestID, candidate));
      return;
    }

    if (candidateRequestID != requestID) {
      return;
    }

    try {
      await offerer.addICECandidate(candidate);
    } catch (e) {
      print(e);
    }
  });

  try {
    final offer = await offerFuture;

    final offerJSON = jsonEncode(offer);

    final callResponse = await config.session.call(config.procedureWebRTCOffer, args: [offerJSON]);

    final offerResponseText = callResponse.args[0] as String;

    final offerResponseMap = jsonDecode(offerResponseText) as Map<String, dynamic>;
    final offerResponse = OfferResponse.fromJson(offerResponseMap);

    if (offerResponse.requestID.isEmpty) {
      throw Exception("offer response request ID must not be empty");
    }

    requestID = offerResponse.requestID;

    final buffered = List<_PendingRemoteCandidate>.from(pendingCandidates);
    pendingCandidates.clear();
    for (final pc in buffered) {
      if (pc.requestID != requestID) {
        continue;
      }
      try {
        await offerer.addICECandidate(pc.candidate);
      } catch (e) {
        print(e);
      }
    }

    offerer.startICETrickle(config.session, offerConfig.topicAnswererOnCandidate, requestID);

    await offerer.handleAnswer(offerResponse.answer);

    final channel = await offerer.waitReady().timeout(
          _connectTimeout,
          onTimeout: () => throw TimeoutException("WebRTC data channel did not open", _connectTimeout),
        );

    return WebRTCSession(
      channel: channel,
      connection: offerer.connection!,
    );
  } catch (e) {
    await offerer.connection?.close();
    rethrow;
  } finally {
    unawaited(subscription.unsubscribe());
  }
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
