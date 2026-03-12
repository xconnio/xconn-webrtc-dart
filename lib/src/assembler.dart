import 'dart:typed_data';
import 'dart:collection';

class MessageAssembler {
	final Map<int, List<int>> _buffers = HashMap();
	final Map<int, int> _expectedLength = HashMap();

	List<int>? feed(Uint8List data) {
		if (data.length < 4) return null;

		final flags = data[0];
		final isFinal = (flags & 0x01) != 0;
		final messageId = ByteData.sublistView(data, 1, 5).getUint32(0);

		if (isFinal) {
			if (data.length <= 5) return null;
			return data.sublist(5);
		}

		if (data.length < 9) return null;
		final length = ByteData.sublistView(data, 5, 9).getUint32(0);

		if (data.length < 9 + length) return null;

		_buffers[messageId] = data.sublist(9, 9 + length).toList();
		_expectedLength[messageId] = length;

		return null;
	}

	List<int>? addFragment(int messageId, Uint8List fragment, bool isFinal) {
		if (!_buffers.containsKey(messageId) || !_expectedLength.containsKey(messageId)) {
			return null;
		}

		_buffers[messageId]!.addAll(fragment);

		if (isFinal) {
			final fullMessage = _buffers.remove(messageId)!;
			_expectedLength.remove(messageId);
			return fullMessage;
		}

		return null;
	}
}
