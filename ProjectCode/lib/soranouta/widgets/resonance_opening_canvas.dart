import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sakiengine/src/core/script_canvas.dart';

const String resonanceOpeningCanvasId = 'soranouta.magnetic_wait';

const ScriptCanvasDefinition resonanceOpeningCanvas = ScriptCanvasDefinition(
  paint: _paintResonanceOpening,
);

void _paintResonanceOpening(Canvas canvas, Size size, double progress) {
  if (size.isEmpty) return;

  final bounds = Offset.zero & size;
  final unit = math.min(size.width, size.height);
  canvas.drawRect(bounds, Paint()..color = const Color(0xFF030405));

  final fade =
      _smoothStep(0.03, 0.14, progress) * (1 - _smoothStep(0.88, 1, progress));
  canvas.saveLayer(bounds, Paint()..color = Colors.white.withOpacity(fade));

  _paintPaper(canvas, size, unit);
  _paintMagneticField(canvas, size, progress, unit);
  _paintNeedle(canvas, size, progress, unit);
  _paintSentence(canvas, size, progress, unit);

  canvas.restore();
}

void _paintPaper(Canvas canvas, Size size, double unit) {
  final bounds = Offset.zero & size;
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFF0B0C0E),
          Color(0xFF070809),
          Color(0xFF101012),
          Color(0xFF050607),
        ],
        stops: <double>[0, 0.36, 0.68, 1],
      ).createShader(bounds),
  );

  final fiberPaint = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeWidth = math.max(0.35, unit * 0.00045);
  for (var i = 0; i < 96; i++) {
    final x = _hash(i * 19 + 5) * size.width;
    final y = _hash(i * 31 + 9) * size.height;
    final length = unit * (0.006 + _hash(i * 43 + 2) * 0.032);
    final slope = (_hash(i * 23 + 7) - 0.5) * unit * 0.002;
    fiberPaint.color = const Color(
      0xFFD8D5CB,
    ).withOpacity(0.012 + _hash(i * 11) * 0.025);
    canvas.drawLine(Offset(x, y), Offset(x + length, y + slope), fiberPaint);
  }

  canvas.drawRect(
    bounds,
    Paint()
      ..shader = RadialGradient(
        radius: 0.82,
        colors: <Color>[
          Colors.transparent,
          const Color(0xFF010102).withOpacity(0.18),
          const Color(0xFF010102).withOpacity(0.76),
        ],
        stops: const <double>[0.32, 0.72, 1],
      ).createShader(bounds),
  );
}

void _paintMagneticField(
  Canvas canvas,
  Size size,
  double progress,
  double unit,
) {
  final opacity = _window(progress, 0.12, 0.25, 0.74, 0.92);
  final center = Offset(size.width * 0.5, size.height * 0.5);
  final linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.45, unit * 0.00055)
    ..color = const Color(0xFFC9C8C1).withOpacity(opacity * 0.095);

  final path = Path();
  const samples = 96;
  for (var i = 0; i <= samples; i++) {
    final x = size.width * i / samples;
    final distance = ((x - center.dx) / (size.width * 0.22)).abs();
    final envelope = math.exp(-distance * distance * 2.8);
    final wave = math.sin(i * 0.34 - progress * math.pi * 3.2);
    final y = center.dy + wave * envelope * unit * 0.006;
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  canvas.drawPath(path, linePaint);

  final ringOpacity = opacity * (0.045 + 0.025 * math.sin(progress * math.pi));
  for (var i = 0; i < 2; i++) {
    final radius = unit * (0.115 + i * 0.095);
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: radius * 2.25,
        height: radius * 0.62,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.4, unit * 0.00045)
        ..color = const Color(0xFFC9C8C1).withOpacity(ringOpacity),
    );
  }
}

void _paintNeedle(Canvas canvas, Size size, double progress, double unit) {
  final opacity = _window(progress, 0.1, 0.24, 0.73, 0.91);
  final center = Offset(size.width * 0.5, size.height * 0.5);
  final arrival = _smoothStep(0.14, 0.31, progress);
  final damping = 1 - _smoothStep(0.32, 0.6, progress);
  final vibration =
      math.sin(progress * math.pi * 15) * 0.026 * damping * arrival;
  final angle = -math.pi / 2 + vibration;
  final direction = Offset(math.cos(angle), math.sin(angle));
  final tip = center + direction * unit * 0.205;
  final tail = center - direction * unit * 0.055;

  canvas.drawLine(
    tail,
    tip,
    Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.8, unit * 0.00115)
      ..color = const Color(0xFFD8D5CB).withOpacity(opacity * 0.62),
  );
  canvas.drawCircle(
    center,
    math.max(1.5, unit * 0.0042),
    Paint()..color = const Color(0xFFCBC8BE).withOpacity(opacity * 0.72),
  );
  canvas.drawCircle(
    center,
    unit * 0.015,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.45, unit * 0.0006)
      ..color = const Color(0xFFC4C2BA).withOpacity(opacity * 0.16),
  );
}

void _paintSentence(Canvas canvas, Size size, double progress, double unit) {
  final firstOpacity = _smoothStep(0.28, 0.41, progress);
  final secondOpacity = _smoothStep(0.43, 0.57, progress);
  final departure = 1 - _smoothStep(0.82, 0.93, progress);
  final fracture = _smoothStep(0.52, 0.72, progress);

  _paintFracturedText(
    canvas,
    text: '每当磁针再次振动，',
    origin: Offset(size.width * 0.205, size.height * 0.365),
    fontSize: unit * 0.057,
    opacity: firstOpacity * departure * 0.88,
    fracture: fracture,
  );
  _paintFracturedText(
    canvas,
    text: '我便在此等待。',
    origin: Offset(size.width * 0.465, size.height * 0.595),
    fontSize: unit * 0.062,
    opacity: secondOpacity * departure * 0.92,
    fracture: fracture,
  );
}

void _paintFracturedText(
  Canvas canvas, {
  required String text,
  required Offset origin,
  required double fontSize,
  required double opacity,
  required double fracture,
}) {
  if (opacity <= 0) return;

  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: const Color(0xFFE2DED2).withOpacity(opacity),
        fontFamily: 'ChillJinshuSongPro_Soft',
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        letterSpacing: fontSize * 0.135,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final shift = fontSize * 0.055 * fracture;
  final firstEnd = painter.height * 0.37;
  final secondStart = painter.height * 0.41;
  final secondEnd = painter.height * 0.69;
  final thirdStart = painter.height * 0.73;

  canvas.save();
  canvas.translate(origin.dx, origin.dy);

  canvas.save();
  canvas.clipRect(Rect.fromLTWH(0, 0, painter.width, firstEnd));
  painter.paint(canvas, Offset(-shift, 0));
  canvas.restore();

  canvas.save();
  canvas.clipRect(
    Rect.fromLTWH(0, secondStart, painter.width, secondEnd - secondStart),
  );
  painter.paint(canvas, Offset(shift * 0.7, 0));
  canvas.restore();

  canvas.save();
  canvas.clipRect(
    Rect.fromLTWH(0, thirdStart, painter.width, painter.height - thirdStart),
  );
  painter.paint(canvas, Offset(-shift * 0.35, 0));
  canvas.restore();

  canvas.restore();
}

double _window(
  double value,
  double fadeInStart,
  double fadeInEnd,
  double fadeOutStart,
  double fadeOutEnd,
) {
  return _smoothStep(fadeInStart, fadeInEnd, value) *
      (1 - _smoothStep(fadeOutStart, fadeOutEnd, value));
}

double _smoothStep(double edge0, double edge1, double value) {
  if (edge0 == edge1) return value < edge0 ? 0 : 1;
  final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0).toDouble();
  return t * t * (3 - 2 * t);
}

double _hash(int seed) {
  final value = math.sin(seed * 12.9898 + 78.233) * 43758.5453;
  return value.abs() - value.abs().floorToDouble();
}
