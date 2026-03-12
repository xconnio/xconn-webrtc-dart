enum Role {
  offerer,
  answerer,
}

class WebRTCTransport {
  final dynamic dataChannel;
  final Function(List<int>) onMessage;
  final Function() onClose;
  final Function(Object) onError;

  WebRTCTransport({
    required this.dataChannel,
    required this.onMessage,
    required this.onClose,
    required this.onError,
  });
}
