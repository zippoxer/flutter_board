import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_contractor/net.dart' as net;
import 'package:web_contractor/board.dart' as board;

net.Connection connection;
const bgColor = Color.fromARGB(255, 1, 22, 39);
const standardSize = Size(411.4, 671.4);

class BoardPainter extends ChangeNotifier implements CustomPainter {
  List<board.Element> elements;

  BoardPainter(this.elements);

  bool hitTest(Offset position) => null;

  void update() {
    notifyListeners();
  }

  void paint(Canvas canvas, Size size) {
    // Scale to match my OnePlus 3T.
    canvas.scale(
        size.width / standardSize.width, size.height / standardSize.height);

    canvas.drawColor(bgColor, BlendMode.src);

    for (var element in elements) {
      element.draw(canvas, size);
    }
  }

  bool shouldRepaint(BoardPainter other) {
    return true;
  }

  // TODO: implement semanticsBuilder
  @override
  SemanticsBuilderCallback get semanticsBuilder => null;

  @override
  bool shouldRebuildSemantics(CustomPainter oldDelegate) {
    // TODO: implement shouldRebuildSemantics
  }
}

class BoardWidget extends StatefulWidget {
  BoardState createState() => BoardState();
}

class BoardState extends State<BoardWidget>
    with SingleTickerProviderStateMixin {
  bool _online = false;
  int _userId;
  var _strokeStyle = board.StrokeStyle()
    ..color = Colors.teal
    ..width = 4.0;
  var _elements = List<board.Element>();
  var _activeStrokes = Map<int, board.Stroke>();

  initState() {
    super.initState();
    _painter = BoardPainter(_elements);
    connection = net.Connection("zippo.io", 3939, onConnect, onMessage);
  }

  onConnect() {
    print("online!");
    setState(() => _online = true);
  }

  onMessage(net.Message msg) {
    // print("got msg ${msg.type.toString()}");
    switch (msg.runtimeType) {
      case net.WelcomeMessage:
        net.WelcomeMessage m = msg;
        setState(() {
          _userId = m.userId;
          _strokeStyle.color = m.color;
        });
        break;
      case net.ClearMessage:
        _elements.clear();
        _painter.update();
        break;
      case net.StartStrokeMessage:
        net.StartStrokeMessage m = msg;
        var stroke = board.Stroke()
          ..userId = m.userId
          ..elementId = m.strokeId
          ..style = m.style
          ..points = [m.origin];
        _elements.add(stroke);
        var strokeId = (m.userId * 1000) + m.strokeId;
        _activeStrokes[strokeId] = stroke;
        _painter.update();
        break;
      case net.AdvanceStrokeMessage:
        net.AdvanceStrokeMessage m = msg;
        var strokeId = (m.userId * 1000) + m.strokeId;
        var stroke = _activeStrokes[strokeId];
        if (stroke != null) {
          var lastPoint = stroke.points.last;
          stroke.points.add(lastPoint.translate(m.offset.dx, m.offset.dy));
          _painter.update();
        } else {
          print("stroke is null in AdvanceStrokeMessage");
        }
        break;
      case net.EndStrokeMessage:
        net.EndStrokeMessage m = msg;
        var strokeId = (m.userId * 1000) + m.strokeId;
        var stroke = _activeStrokes[strokeId];
        if (stroke != null) {
          var lastPoint = stroke.points.last;
          stroke.points.add(lastPoint.translate(m.offset.dx, m.offset.dy));
          _painter.update();
        } else {
          print("stroke is null in EndStrokeMessage");
        }
        break;
    }
  }

  Offset _translatePoint(Offset point) {
    RenderBox box = _paintKey.currentContext.findRenderObject();
    point = box.globalToLocal(point);
    return Offset(standardSize.width / box.size.width * point.dx,
        standardSize.height / box.size.height * point.dy);
  }

  void _onPointerDown(PointerDownEvent ev) {
    if (_userId == null) {
      return;
    }

    var point = _translatePoint(ev.position);

    var strokeStyle = (board.StrokeStyle()
      ..color = _strokeStyle.color
      ..width = _strokeStyle.width);

    var stroke = board.Stroke()
      ..elementId =
          Random(DateTime.now().microsecondsSinceEpoch).nextInt(pow(2, 32) - 1)
      ..points = [point]
      ..style = strokeStyle;
    _elements.add(stroke);
    _activeStrokes[ev.device] = stroke;
    _painter.update();

    // send StartStrokeMessage
    var msg = net.StartStrokeMessage()
      ..userId = _userId
      ..strokeId = ev.device
      ..origin = point
      ..style = strokeStyle;
    connection.send(msg);
  }

  void _onPointerMove(PointerMoveEvent ev) {
    if (_userId == null) {
      return;
    }

    double sensitivity = 8.0;
    var point = _translatePoint(ev.position);
    var stroke = _activeStrokes[ev.device];
    var prevPoint = stroke.points.last;
    var distance = sqrt(pow((prevPoint.dx - point.dx).abs(), 2) +
        pow((prevPoint.dy - point.dy).abs(), 2));
    if (distance >= sensitivity) {
      stroke.points.add(point);
      stroke.activePoint = null;
      _painter.update();

      // send AdvanceStrokeMessage
      var msg = net.AdvanceStrokeMessage()
        ..userId = _userId
        ..strokeId = ev.device
        ..offset = point.translate(-prevPoint.dx, -prevPoint.dy);
      connection.send(msg);
    } else if (distance >= 2) {
      stroke.activePoint = point;
      _painter.update();
    }
  }

  void _onPointerUp(PointerUpEvent ev) {
    if (_userId == null) {
      return;
    }

    var point = _translatePoint(ev.position);
    var stroke = _activeStrokes[ev.device];
    stroke.points.add(point);
    stroke.activePoint = null;
    _painter.update();

    // send EndStrokeMssage
    var msg = net.EndStrokeMessage()
      ..userId = _userId
      ..strokeId = ev.device
      ..offset =
          point.translate(-stroke.points.last.dx, -stroke.points.last.dy);
    connection.send(msg);
  }

  GlobalKey _paintKey = GlobalKey();
  BoardPainter _painter;

  Widget build(BuildContext context) {
    if (!_online) {
      return Scaffold(
        primary: false,
        backgroundColor: bgColor,
        body: Center(child: Text("Connecting...")),
      );
    }
    return Scaffold(
      primary: false,
      resizeToAvoidBottomPadding: false,
      appBar: PreferredSize(
        preferredSize: Size(.0, 60.0),
        child: Container(
          padding: EdgeInsets.only(left: 20.0, right: 20.0),
          color: Colors.black12,
          child: Row(
            children: <Widget>[
              Container(
                width: 15.0,
                child: Icon(Icons.brush, size: 15.0),
              ),
              Container(
                width: 100.0,
                child: Slider(
                  value: _strokeStyle.width,
                  min: 1.0,
                  max: 30.0,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white30,
                  onChanged: (value) =>
                      setState(() => _strokeStyle.width = value),
                ),
              ),
              Container(
                width: 30.0,
                child: Icon(Icons.brush, size: 30.0),
              ),
              Expanded(
                child: IconButton(
                  icon: Icon(Icons.format_paint),
                  alignment: Alignment.centerRight,
                  onPressed: () => setState(() {
                        _elements.clear();
                        connection.send(net.ClearMessage()..userId = _userId);
                      }),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              child: CustomPaint(
                key: _paintKey,
                painter: _painter,
                child: ConstrainedBox(
                  constraints: BoxConstraints.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BoardApp extends StatelessWidget {
  Widget build(BuildContext context) => BoardWidget();
}

void main() {
  SystemChrome.setEnabledSystemUIOverlays([]);
  runApp(MaterialApp(
    title: "Boared",
    home: BoardApp(),
    theme: ThemeData.dark(),
    debugShowCheckedModeBanner: false,
  ));
}
