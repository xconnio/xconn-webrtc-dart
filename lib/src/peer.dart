import 'package:flutter_webrtc/flutter_webrtc.dart';

class Peer {
  late final RTCPeerConnection pc;
  final List<RTCDataChannel> channels = [];
  final Map<String, dynamic> config;

  Peer({required this.config});

  Future<void> init() async {
    pc = await createPeerConnection(config);
  }

  Future<RTCDataChannel> createDataChannel(
      String label, {
        RTCDataChannelInit? options,
      }) async {
    final channel = await pc.createDataChannel(
      label,
      options ?? RTCDataChannelInit(),
    );

    channels.add(channel);
    return channel;
  }

  Future<RTCSessionDescription> createOffer() async {
    return pc.createOffer();
  }

  Future<RTCSessionDescription> createAnswer() async {
    return pc.createAnswer();
  }

  Future<void> setLocalDescription(RTCSessionDescription desc) async {
    await pc.setLocalDescription(desc);
  }

  Future<void> setRemoteDescription(RTCSessionDescription desc) async {
    await pc.setRemoteDescription(desc);
  }

  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await pc.addCandidate(candidate);
  }

  void close() {
    for (var channel in channels) {
      channel.close();
    }
    pc.close();
  }
}
