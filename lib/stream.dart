import 'dart:typed_data';

// enum ByteOrder
const int LITTLE_ENDIAN = 0;
const int BIG_ENDIAN = 1;

/// A buffer that can be read as a stream of bytes.
class InputStream {
  final List<int> buffer;
  int offset;
  final int start;
  final int byteOrder;

  /// Create a InputStream for reading from a List<int>
  InputStream(data, {this.byteOrder: LITTLE_ENDIAN, int start: 0, int length})
      : this.buffer = data is ByteData ? new Uint8List.view(data.buffer) : data,
        this.start = start {
    _length = length == null ? buffer.length : length;
    offset = start;
  }

  /// Create a copy of [other].
  InputStream.from(InputStream other)
      : buffer = other.buffer,
        offset = other.offset,
        start = other.start,
        _length = other._length,
        byteOrder = other.byteOrder;

  /// The current read position relative to the start of the buffer.
  int get position => offset - start;

  /// How many bytes are left in the stream.
  int get length => _length - (offset - start);

  /// Is the current position at the end of the stream?
  bool get isEOS => offset >= (start + _length);

  /// Reset to the beginning of the stream.
  void reset() {
    offset = start;
  }

  /// Access the buffer relative from the current position.
  int operator [](int index) => buffer[offset + index];

  /// Return a InputStream to read a subset of this stream.  It does not
  /// move the read position of this stream.  [position] is specified relative
  /// to the start of the buffer.  If [position] is not specified, the current
  /// read position is used. If [length] is not specified, the remainder of this
  /// stream is used.
  InputStream subset([int position, int length]) {
    if (position == null) {
      position = this.offset;
    } else {
      position += start;
    }

    if (length == null || length < 0) {
      length = _length - (position - start);
    }

    return new InputStream(buffer,
        byteOrder: byteOrder, start: position, length: length);
  }

  /// Returns the position of the given [value] within the buffer, starting
  /// from the current read position with the given [offset].  The position
  /// returned is relative to the start of the buffer, or -1 if the [value]
  /// was not found.
  int indexOf(int value, [int offset = 0]) {
    for (int i = this.offset + offset, end = this.offset + length;
        i < end;
        ++i) {
      if (buffer[i] == value) {
        return i - this.start;
      }
    }
    return -1;
  }

  /// Read [count] bytes from an [offset] of the current read position, without
  /// moving the read position.
  InputStream peekBytes(int count, [int offset = 0]) {
    return subset((this.offset - start) + offset, count);
  }

  /// Move the read position by [count] bytes.
  void skip(int count) {
    offset += count;
  }

  /// Read a single byte.
  int readByte() {
    return buffer[offset++];
  }

  int readInt8() {
    return readByte().toSigned(8);
  }

  /// Read [count] bytes from the stream.
  InputStream readBytes(int count) {
    InputStream bytes = subset(this.offset - start, count);
    offset += bytes.length;
    return bytes;
  }

  /// Read a null-terminated string, or if [len] is provided, that number of
  /// bytes returned as a string.
  String readString([int len]) {
    if (len == null) {
      List<int> codes = [];
      while (!isEOS) {
        int c = readByte();
        if (c == 0) {
          return new String.fromCharCodes(codes);
        }
        codes.add(c);
      }
      throw new Exception('EOF reached without finding string terminator');
    }

    InputStream s = readBytes(len);
    Uint8List bytes = s.toUint8List();
    String str = new String.fromCharCodes(bytes);
    return str;
  }

  /// Read a 16-bit word from the stream.
  int readUint16() {
    int b1 = buffer[offset++] & 0xff;
    int b2 = buffer[offset++] & 0xff;
    if (byteOrder == BIG_ENDIAN) {
      return (b1 << 8) | b2;
    }
    return (b2 << 8) | b1;
  }

  int readInt16() {
    return readUint16().toSigned(16);
  }

  /// Read a 24-bit word from the stream.
  int readUint24() {
    int b1 = buffer[offset++] & 0xff;
    int b2 = buffer[offset++] & 0xff;
    int b3 = buffer[offset++] & 0xff;
    if (byteOrder == BIG_ENDIAN) {
      return b3 | (b2 << 8) | (b1 << 16);
    }
    return b1 | (b2 << 8) | (b3 << 16);
  }

  /// Read a 32-bit word from the stream.
  int readUint32() {
    int b1 = buffer[offset++] & 0xff;
    int b2 = buffer[offset++] & 0xff;
    int b3 = buffer[offset++] & 0xff;
    int b4 = buffer[offset++] & 0xff;
    if (byteOrder == BIG_ENDIAN) {
      return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
    }
    return (b4 << 24) | (b3 << 16) | (b2 << 8) | b1;
  }

  int readInt32() {
    return readUint32().toSigned(32);
  }

  /// Read a 64-bit word form the stream.
  int readUint64() {
    int b1 = buffer[offset++] & 0xff;
    int b2 = buffer[offset++] & 0xff;
    int b3 = buffer[offset++] & 0xff;
    int b4 = buffer[offset++] & 0xff;
    int b5 = buffer[offset++] & 0xff;
    int b6 = buffer[offset++] & 0xff;
    int b7 = buffer[offset++] & 0xff;
    int b8 = buffer[offset++] & 0xff;
    if (byteOrder == BIG_ENDIAN) {
      return (b1 << 56) |
          (b2 << 48) |
          (b3 << 40) |
          (b4 << 32) |
          (b5 << 24) |
          (b6 << 16) |
          (b7 << 8) |
          b8;
    }
    return (b8 << 56) |
        (b7 << 48) |
        (b6 << 40) |
        (b5 << 32) |
        (b4 << 24) |
        (b3 << 16) |
        (b2 << 8) |
        b1;
  }

  int readInt64() {
    return readUint64().toSigned(64);
  }

  Uint8List toUint8List() {
    int len = length;
    if (buffer is Uint8List) {
      Uint8List b = buffer;
      Uint8List bytes = new Uint8List.view(b.buffer, offset, len);
      return bytes;
    }
    return new Uint8List.fromList(buffer.sublist(offset, offset + len));
  }

  int _length;
}

class OutputStream {
  int length;
  final int byteOrder;

  /// Create a byte buffer for writing.
  OutputStream({int size: _BLOCK_SIZE, this.byteOrder: LITTLE_ENDIAN})
      : _buffer = new Uint8List(size == null ? _BLOCK_SIZE : size),
        length = 0;

  /// Get the resulting bytes from the buffer.
  List<int> getBytes() {
    return new Uint8List.view(_buffer.buffer, 0, length);
  }

  /// Clear the buffer.
  void clear() {
    _buffer = new Uint8List(_BLOCK_SIZE);
    length = 0;
  }

  /// Reset the buffer.
  void reset() {
    length = 0;
  }

  /// Write a byte to the end of the buffer.
  void writeByte(int value) {
    if (length == _buffer.length) {
      _expandBuffer();
    }
    _buffer[length++] = value & 0xff;
  }

  void writeInt8(int value) {
    writeByte(value.toSigned(8));
  }

  /// Write a set of bytes to the end of the buffer.
  void writeBytes(List<int> bytes, [int len]) {
    if (len == null) {
      len = bytes.length;
    }
    while (length + len > _buffer.length) {
      _expandBuffer((length + len) - _buffer.length);
    }
    _buffer.setRange(length, length + len, bytes);
    length += len;
  }

  void writeInputStream(InputStream bytes) {
    while (length + bytes.length > _buffer.length) {
      _expandBuffer((length + bytes.length) - _buffer.length);
    }
    _buffer.setRange(length, length + bytes.length, bytes.buffer, bytes.offset);
    length += bytes.length;
  }

  /// Write a 16-bit word to the end of the buffer.
  void writeUint16(int value) {
    if (byteOrder == BIG_ENDIAN) {
      writeByte((value >> 8) & 0xff);
      writeByte((value) & 0xff);
      return;
    }
    writeByte((value) & 0xff);
    writeByte((value >> 8) & 0xff);
  }

  void writeInt16(int value) {
    writeUint16(value.toSigned(16));
  }

  /// Write a 32-bit word to the end of the buffer.
  void writeUint32(int value) {
    if (byteOrder == BIG_ENDIAN) {
      writeByte((value >> 24) & 0xff);
      writeByte((value >> 16) & 0xff);
      writeByte((value >> 8) & 0xff);
      writeByte((value) & 0xff);
      return;
    }
    writeByte((value) & 0xff);
    writeByte((value >> 8) & 0xff);
    writeByte((value >> 16) & 0xff);
    writeByte((value >> 24) & 0xff);
  }

  void writeInt32(int value) {
    writeUint32(value.toSigned(32));
  }

  /// Return the subset of the buffer in the range [start:end].
  /// If [start] or [end] are < 0 then it is relative to the end of the buffer.
  /// If [end] is not specified (or null), then it is the end of the buffer.
  /// This is equivalent to the python list range operator.
  List<int> subset(int start, [int end]) {
    if (start < 0) {
      start = (length) + start;
    }

    if (end == null) {
      end = length;
    } else if (end < 0) {
      end = length + end;
    }

    return new Uint8List.view(_buffer.buffer, start, end - start);
  }

  /// Grow the buffer to accommodate additional data.
  void _expandBuffer([int required]) {
    int blockSize = _BLOCK_SIZE;
    if (required != null) {
      if (required > blockSize) {
        blockSize = required;
      }
    }
    Uint8List newBuffer = new Uint8List(_buffer.length + blockSize);
    newBuffer.setRange(0, _buffer.length, _buffer);
    _buffer = newBuffer;
  }

  static const int _BLOCK_SIZE = 0x8000; // 32k block-size
  Uint8List _buffer;
}
