import "dart:async";
import "dart:typed_data";

const int mtuSize = 16 * 1024;

class WebRTCMessageAssembler {
  WebRTCMessageAssembler(this.mtu);

  final BytesBuilder _buffer = BytesBuilder();
  final int mtu;

  Stream<Uint8List> chunkMessage(Uint8List message) async* {
    final chunkSize = mtu - 1;
    final totalChunks = (message.length + chunkSize - 1) ~/ chunkSize;

    for (var i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      var end = start + chunkSize;

      if (i == totalChunks - 1) {
        end = message.length;
      }

      final chunk = message.sublist(start, end);

      final isFinal = (i == totalChunks - 1) ? 1 : 0;

      final out = Uint8List(chunk.length + 1);
      out[0] = isFinal;
      out.setRange(1, out.length, chunk);

      yield out;
    }
  }

  Uint8List? feed(Uint8List data) {
    if (data.isEmpty) {
      return null;
    }

    _buffer.add(data.sublist(1));
    final isFinal = data[0];

    if (isFinal == 1) {
      final out = _buffer.toBytes();
      _buffer.clear();
      return out;
    }

    return null;
  }
}
