library net;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:web_contractor/board.dart';
import 'package:web_contractor/stream.dart';

enum MessageType {
  InvalidMessage,
  HelloMessage,
  WelcomeMessage,
  ClearMessage,
  StartStrokeMessage,
  AdvanceStrokeMessage,
  EndStrokeMessage
}

abstract class Message {
  MessageType get type => MessageType.InvalidMessage;
  void read(InputStream stream);
  void write(OutputStream stream);

  static final _nullPoint =
      Offset((pow(2, 16) - 1).toDouble(), (pow(2, 16) - 1).toDouble());

  Offset _readPoint(InputStream stream) {
    var x = stream.readInt16().toDouble();
    var y = stream.readInt16().toDouble();
    var o = Offset(x, y);
    if (o == _nullPoint) {
      return null;
    }
    return o;
  }

  void _writePoint(OutputStream stream, Offset o) {
    if (o == null) {
      o = _nullPoint;
    }
    stream.writeInt16(o.dx.toInt());
    stream.writeInt16(o.dy.toInt());
  }

  Color _readColor(InputStream stream) {
    var r = stream.readByte(),
        g = stream.readByte(),
        b = stream.readByte(),
        a = stream.readByte();
    return Color.fromARGB(a, r, g, b);
  }

  void _writeColor(OutputStream stream, Color c) {
    stream..writeBytes([c.red, c.green, c.blue, c.alpha]);
  }
}

class HelloMessage extends Message {
  MessageType get type => MessageType.HelloMessage;

  void read(InputStream stream) {}

  void write(OutputStream stream) {}
}

class WelcomeMessage extends Message {
  MessageType get type => MessageType.WelcomeMessage;
  int userId;
  Color color;

  void read(InputStream stream) {
    userId = stream.readByte();
    color = _readColor(stream);
  }

  void write(OutputStream stream) {
    stream.writeByte(userId);
    _writeColor(stream, color);
  }
}

class ClearMessage extends Message {
  MessageType get type => MessageType.ClearMessage;
  int userId;

  void read(InputStream stream) {
    userId = stream.readByte();
  }

  void write(OutputStream stream) {
    stream.writeByte(userId);
  }
}

class StartStrokeMessage extends Message {
  MessageType get type => MessageType.StartStrokeMessage;
  int userId;
  int strokeId; // A single user can draw multiple strokes simultaneously.
  StrokeStyle style;
  Offset origin;

  void read(InputStream stream) {
    userId = stream.readByte();
    strokeId = stream.readByte();
    style = _readStrokeStyle(stream);
    origin = _readPoint(stream);
  }

  void write(OutputStream stream) {
    stream.writeByte(userId);
    stream.writeByte(strokeId);
    _writeStrokeStyle(stream);
    _writePoint(stream, origin);
  }

  StrokeStyle _readStrokeStyle(InputStream stream) {
    return StrokeStyle()
      ..color = _readColor(stream)
      ..width = stream.readUint16() / 10;
  }

  void _writeStrokeStyle(OutputStream stream) {
    _writeColor(stream, style.color);
    stream.writeUint16((style.width * 10).toInt());
  }
}

class AdvanceStrokeMessage extends Message {
  MessageType get type => MessageType.AdvanceStrokeMessage;
  int userId;
  int strokeId;
  Offset offset;

  void read(InputStream stream) {
    userId = stream.readByte();
    strokeId = stream.readByte();
    var x = stream.readInt16().toDouble();
    var y = stream.readInt16().toDouble();
    offset = Offset(x / 100, y / 100);
  }

  void write(OutputStream stream) {
    stream.writeInt8(userId);
    stream.writeInt8(strokeId);
    stream.writeInt16((offset.dx * 100).toInt());
    stream.writeInt16((offset.dy * 100).toInt());
  }
}

class EndStrokeMessage extends Message {
  MessageType get type => MessageType.EndStrokeMessage;
  int userId;
  int strokeId;
  Offset offset;

  void read(InputStream stream) {
    userId = stream.readByte();
    strokeId = stream.readByte();
    var x = stream.readInt8().toDouble();
    var y = stream.readInt8().toDouble();
    offset = Offset(x, y);
  }

  void write(OutputStream stream) {
    stream.writeInt8(userId);
    stream.writeInt8(strokeId);
    stream.writeInt8(offset.dx.toInt());
    stream.writeInt8(offset.dy.toInt());
  }
}

class Connection {
  Socket _socket;
  var _data = List<int>();
  var _dataSize = 0;

  Function(Message msg) _onMessage;

  Connection(
      dynamic host, int port, void onConnect(), void onMessage(Message msg)) {
    this._onMessage = onMessage;
    Socket.connect(host, port).then((socket) {
      _socket = socket;
      onConnect();
      socket.listen(_receive, onDone: () {
        print("socket done!");
      });
    });
  }

  void send(Message msg) {
    var stream = new OutputStream();
    msg.write(stream);

    var size = stream.length + 1;
    // print("sending msg ${msg.type.index} - $size bytes");
    var head = Uint8List(3);
    head.buffer.asByteData()
      ..setUint16(0, size, Endian.little)
      ..setUint8(2, msg.type.index);
    _socket.add(head.toList());

    _socket.add(stream.getBytes());
  }

  void _read(ByteData data) {
    var stream = new InputStream(data);
    var msgId = stream.readByte();
    // print("reading msg id $msgId");
    Message msg;
    MessageType type = MessageType.InvalidMessage;
    if (msgId < MessageType.values.length) {
      type = MessageType.values[msgId];
    }
    switch (type) {
      case MessageType.WelcomeMessage:
        msg = WelcomeMessage();
        break;
      case MessageType.ClearMessage:
        msg = ClearMessage();
        break;
      case MessageType.StartStrokeMessage:
        msg = StartStrokeMessage();
        break;
      case MessageType.AdvanceStrokeMessage:
        msg = AdvanceStrokeMessage();
        break;
      case MessageType.EndStrokeMessage:
        msg = EndStrokeMessage();
        break;
      default:
        print("unknown message id $msgId");
    }
    if (msg != null) {
      msg.read(stream);
      this._onMessage(msg);
    }
  }

  void _receive(List<int> frame, [bool reread]) {
    var read = 0;
    if (_dataSize == 0) {
      _dataSize = Uint8List
          .fromList(frame.take(2).toList())
          .buffer
          .asByteData()
          .getUint16(0, Endian.little);
      var x = frame.skip(2).take(_dataSize);
      read = x.length + 2;
      _data = x.toList();
    } else {
      var x = frame.take(_dataSize - _data.length);
      read = x.length;
      _data.addAll(x);
    }
    if (_data.length == _dataSize) {
      _read(ByteData.view(Uint8List.fromList(_data).buffer));
      _data.clear();
      _dataSize = 0;
    }
    if (frame.length > read) {
      _receive(frame.skip(read).toList(), true);
    }
  }
}
