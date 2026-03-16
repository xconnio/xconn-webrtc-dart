import "dart:async";
import "dart:typed_data";

import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:xconn/xconn.dart";
import "package:xconn_webrtc_dart/xconn_webrtc_dart.dart";

class WebRTCPeer implements Peer {
  WebRTCPeer(this._channel) : _assembler = WebRTCMessageAssembler(mtuSize) {
    _channel.onMessage = (RTCDataChannelMessage msg) {
      final data = msg.binary;

      final toSend = _assembler.feed(Uint8List.fromList(data));

      if (toSend != null) {
        _messageController.add(toSend);
      }
    };
  }

  final RTCDataChannel _channel;
  final WebRTCMessageAssembler _assembler;

  final StreamController<Uint8List> _messageController = StreamController<Uint8List>();

  @override
  Future<Uint8List> read() {
    return _messageController.stream.first;
  }

  @override
  Future<void> write(Object bytes) async {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes as List<int>);

    await for (final chunk in _assembler.chunkMessage(data)) {
      await _channel.send(RTCDataChannelMessage.fromBinary(chunk));
    }
  }

  @override
  Future<void> close() async {
    await _channel.close();
  }
}
