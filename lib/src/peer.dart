import "dart:async";
import "dart:typed_data";

import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:xconn/xconn.dart";
import "package:xconn_webrtc_dart/xconn_webrtc_dart.dart";

class WebRTCPeerClosedException implements Exception {
  WebRTCPeerClosedException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WebRTCPeer implements Peer {
  WebRTCPeer(this._channel) : _assembler = WebRTCMessageAssembler(mtuSize) {
    _iterator = StreamIterator<Uint8List>(_messageController.stream);

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
  late final StreamIterator<Uint8List> _iterator;

  @override
  Future<Uint8List> read() async {
    if (await _iterator.moveNext()) {
      return _iterator.current;
    }

    throw WebRTCPeerClosedException("WebRTC data channel closed");
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
    await _iterator.cancel();
    await _messageController.close();
    await _channel.close();
  }
}
