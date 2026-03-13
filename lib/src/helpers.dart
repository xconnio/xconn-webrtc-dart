import "package:wampproto/serializers.dart";

const String jsonSubProtocol = "wamp.2.json";
const String cborSubProtocol = "wamp.2.cbor";
const String msgpackSubProtocol = "wamp.2.msgpack";

String getSubProtocol(Serializer serializer) {
  if (serializer is JSONSerializer) {
    return jsonSubProtocol;
  } else if (serializer is CBORSerializer) {
    return cborSubProtocol;
  } else if (serializer is MsgPackSerializer) {
    return msgpackSubProtocol;
  } else {
    throw ArgumentError("invalid serializer");
  }
}
