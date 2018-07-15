library board;

import 'dart:math';
import 'dart:ui';

import 'package:flutter/painting.dart';

abstract class Element {
  int userId;
  int elementId;
  void draw(Canvas canvas, Size size);
}

class StrokeStyle {
  Color color;
  double width;
}

class Stroke extends Element {
  StrokeStyle style;
  List<Offset> points = List();
  Offset activePoint;
  Paint _paint;
  Path _path;
  int _pathCursor = 0;

  void draw(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    if (_paint == null) {
      _paint = new Paint()
        ..color = style.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = style.width
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
    }
    if (_pathCursor == points.length - 1 && _path != null) {
      canvas.drawPath(_path, _paint);
      return;
    }

    if (_path == null) {
      _path = Path();
      _path.moveTo(points.first.dx, points.first.dy);
    }
    if (points.length == 1) {
      _path.lineTo(points.first.dx, points.first.dy);
    } else {
      for (var i = _pathCursor ?? 0; i < points.length; i++) {
        Offset current = points[i], next;
        if (i < points.length - 1) {
          next = points[i + 1];
        } else {
          if (activePoint == null) {
            break;
          }
          next = activePoint;
        }
        var xMid = (current.dx + next.dx) / 2;
        var yMid = (current.dy + next.dy) / 2;
        var cpX1 = (xMid + current.dx) / 2;
        var cpY1 = (yMid + current.dy) / 2;
        var cpX2 = (xMid + next.dx) / 2;
        var cpY2 = (yMid + next.dy) / 2;
        _path.cubicTo(cpX1, cpY1, cpX2, cpY2, xMid, yMid);
      }
    }
    _pathCursor = points.length - 1;
    canvas.drawPath(_path, _paint);
  }
}

List<Color> triad(Color color) {
  var hsv = HSVColor.fromColor(color);
  var h1 = (hsv.hue + 120) % 360.0, h2 = (h1 + 120) % 360.0;
  return [
    HSVColor.fromAHSV(hsv.alpha, h1, hsv.saturation, hsv.value).toColor(),
    color,
    HSVColor.fromAHSV(hsv.alpha, h2, hsv.saturation, hsv.value).toColor()
  ];
}
