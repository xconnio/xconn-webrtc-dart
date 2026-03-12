import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'peer.dart';

class Offerer {
  final Peer peer;
  RTCDataChannel? _dataChannel;
  Function(Uint8List)? onMessage;
  Function()? onClose;
  Function(dynamic)? onError;

  Offerer({required Map<String, dynamic> config}) : peer = Peer(config: config);

  Future<RTCSessionDescription> connect(String label) async {
    _dataChannel = await peer.createDataChannel(label);

    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      if (onMessage != null && message.isBinary) {
        onMessage!(message.binary);
      }
    };

    _dataChannel!.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelClosed && onClose != null) {
        onClose!();
      }
    };

    return await peer.createOffer();
  }

  Future<void> setRemoteDescription(RTCSessionDescription desc) async {
    await peer.setRemoteDescription(desc);
  }

  void onICECandidate(Function(RTCIceCandidate) callback) {
    peer.pc.onIceCandidate = (candidate) {
      callback(candidate);
        };
  }

  void close() {
    peer.close();
  }
}
