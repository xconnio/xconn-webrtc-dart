import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wampproto/serializers.dart' as wamp;

import 'provider.dart';

class WebRTCClient {
  final wamp.Serializer serializer;
  final WebRTCProvider provider;

  WebRTCClient(this.serializer, this.provider);

  Future<RTCDataChannel> connect(
      String realm, Map<String, dynamic> details) async {

    final channel = await provider.waitForDataChannel();

    return channel;
  }

  void close() {
    provider.close();
  }
}