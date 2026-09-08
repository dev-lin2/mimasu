/// Minimal protobuf wire-format reader.
///
/// Mimasu has no `.proto` for `index.pb` (INSTRUCTIONS.md section 6.2), so it
/// reads the wire format directly by field number. That is stable in a way a
/// guessed schema is not: protobuf is designed so unknown fields can be
/// skipped, which means a repository adding fields cannot break this parser.
library;

/// Protobuf wire types. Groups (3, 4) are deprecated and unsupported.
class WireType {
  static const varint = 0;
  static const fixed64 = 1;
  static const lengthDelimited = 2;
  static const fixed32 = 5;
}

/// Thrown when the payload is not decodable as protobuf at all.
class ProtobufFormatException implements Exception {
  ProtobufFormatException(this.message);
  final String message;
  @override
  String toString() => 'ProtobufFormatException: $message';
}

/// One field as it appears on the wire.
class WireField {
  WireField.varint(this.number, this.intValue)
    : wireType = WireType.varint,
      bytes = null;
  WireField.bytes(this.number, this.bytes)
    : wireType = WireType.lengthDelimited,
      intValue = null;
  WireField.opaque(this.number, this.wireType) : intValue = null, bytes = null;

  final int number;
  final int wireType;
  final int? intValue;
  final List<int>? bytes;
}

/// Splits one protobuf message into its fields, in wire order.
///
/// Repeated fields appear multiple times; callers decide whether to take the
/// first, the last, or all of them.
List<WireField> readMessage(List<int> data) {
  final out = <WireField>[];
  var pos = 0;

  int? readVarint() {
    var result = 0;
    var shift = 0;
    while (pos < data.length) {
      final byte = data[pos++];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
      if (shift > 63) return null;
    }
    return null;
  }

  while (pos < data.length) {
    final key = readVarint();
    if (key == null) {
      throw ProtobufFormatException('truncated field key at $pos');
    }
    final number = key >> 3;
    final wireType = key & 7;
    if (number == 0) {
      throw ProtobufFormatException('invalid field number 0 at $pos');
    }

    switch (wireType) {
      case WireType.varint:
        final value = readVarint();
        if (value == null) {
          throw ProtobufFormatException('truncated varint for field $number');
        }
        out.add(WireField.varint(number, value));
      case WireType.lengthDelimited:
        final length = readVarint();
        if (length == null || pos + length > data.length) {
          throw ProtobufFormatException(
            'truncated length-delimited field $number',
          );
        }
        out.add(WireField.bytes(number, data.sublist(pos, pos + length)));
        pos += length;
      case WireType.fixed64:
        if (pos + 8 > data.length) {
          throw ProtobufFormatException('truncated fixed64 field $number');
        }
        pos += 8;
        out.add(WireField.opaque(number, wireType));
      case WireType.fixed32:
        if (pos + 4 > data.length) {
          throw ProtobufFormatException('truncated fixed32 field $number');
        }
        pos += 4;
        out.add(WireField.opaque(number, wireType));
      default:
        throw ProtobufFormatException(
          'unsupported wire type $wireType for field $number',
        );
    }
  }
  return out;
}

/// Convenience lookups over a decoded message.
extension WireFields on List<WireField> {
  List<int>? bytesOf(int number) {
    for (final f in this) {
      if (f.number == number && f.bytes != null) return f.bytes;
    }
    return null;
  }

  int? intOf(int number) {
    for (final f in this) {
      if (f.number == number && f.intValue != null) return f.intValue;
    }
    return null;
  }

  Iterable<List<int>> allBytesOf(int number) =>
      where((f) => f.number == number && f.bytes != null).map((f) => f.bytes!);
}
