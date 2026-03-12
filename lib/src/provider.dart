import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'peer.dart';
import 'assembler.dart';

class WebRTCProvider {
  final Peer peer;
  RTCDataChannel? _dataChannel;
  final MessageAssembler _assembler = MessageAssembler();
  final _dataChannelReady = Completer<RTCDataChannel>();
  StreamController<Uint8List>? _messageController;

  WebRTCProvider({required Map<String, dynamic> config}) : peer = Peer(config: config);

  Future<RTCDataChannel> waitForDataChannel() {
    peer.pc.onDataChannel = (channel) {
      _dataChannel = channel;
      _dataChannelReady.complete(channel);

      channel.onMessage = (RTCDataChannelMessage message) {
        if (!message.isBinary) return;

        final result = _assembler.feed(message.binary);
        if (result != null && _messageController != null) {
          _messageController!.add(Uint8List.fromList(result));
        }
      };
    };

    return _dataChannelReady.future;
  }

  Stream<Uint8List> messages() {
    _messageController = StreamController<Uint8List>();
    return _messageController!.stream;
  }

  Future<void> send(Uint8List data) async {
    if (_dataChannel == null) {
      throw StateError('Data channel not ready');
    }

    const maxMessageSize = 16384; // Standard WebRTC data channel MTU

    if (data.length <= maxMessageSize) {
      final header = Uint8List(5);
      header[0] = 0x01; // final flag
      header.setRange(1, 5, Uint8List(4)..buffer.asByteData().setUint32(0, 0));

      final completeMessage = Uint8List(header.length + data.length)
        ..setAll(0, header)
        ..setAll(header.length, data);

      await _dataChannel!.send(RTCDataChannelMessage.fromBinary(completeMessage));
      return;
    }

    // Fragment large messages
    final messageId = DateTime.now().millisecondsSinceEpoch;
    var offset = 0;
    var fragmentIndex = 0;

    while (offset < data.length) {
      final fragmentSize = maxMessageSize - 9;
      final end = (offset + fragmentSize < data.length)
          ? offset + fragmentSize
          : data.length;

      final fragment = data.sublist(offset, end);
      final isFinal = end == data.length;

      final header = Uint8List(9);
      header[0] = isFinal ? 0x00 : 0x02;

      ByteData.view(header.buffer, 1, 4).setUint32(0, messageId);
      ByteData.view(header.buffer, 5, 4).setUint32(0, fragmentIndex++);

      final completeFragment = Uint8List(header.length + fragment.length)
        ..setAll(0, header)
        ..setAll(header.length, fragment);

      await _dataChannel!.send(RTCDataChannelMessage.fromBinary(completeFragment));
      offset = end;
    }
  }

  void close() {
    _messageController?.close();
    peer.close();
  }
}
