import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'peer.dart';

class Answerer {
	final Peer peer;
	RTCDataChannel? _dataChannel;
	Function(Uint8List)? onMessage;
	Function()? onClose;
	Function(dynamic)? onError;

	Answerer({required Map<String, dynamic> config}) : peer = Peer(config: config);

	Future<RTCSessionDescription> connect(RTCSessionDescription offer) async {
		await peer.setRemoteDescription(offer);

		peer.pc.onDataChannel = (channel) {
			_dataChannel = channel;

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
		};

		return await peer.createAnswer();
	}

	Future<void> setLocalDescription(RTCSessionDescription desc) async {
		await peer.setLocalDescription(desc);
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
