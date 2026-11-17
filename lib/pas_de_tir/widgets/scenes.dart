import 'package:flutter/material.dart';

/// Carte de course stylisée avec la trace.
class RaceMapPainter extends CustomPainter {
  RaceMapPainter({required this.userProgress});

  /// Avancement de l'utilisateur sur la trace, de 0 (bas de l'écran) à 1 (haut).
  final double userProgress;

  static Path tracePath(Size s) {
    final w = s.width / 390, h = s.height / 844;
    return Path()
      ..moveTo(193 * w, 844 * h)
      ..lineTo(193 * w, 620 * h)
      ..quadraticBezierTo(196 * w, 450 * h, 204 * w, 400 * h)
      ..lineTo(204 * w, 300 * h)
      ..quadraticBezierTo(205 * w, 240 * h, 300 * w, 120 * h)
      ..lineTo(355 * w, 42 * h);
  }

  static Offset poiPosition(Size s) => Offset(204 * s.width / 390, 400 * s.height / 844);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 390, h = size.height / 844;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFDCE6D3));

    final green = Paint()..color = const Color(0xFFA8D69E);
    final light = Paint()..color = const Color(0xFFC3E3BB);
    final beige = Paint()..color = const Color(0xFFE5DED5);
    canvas.drawPath(
        Path()
          ..moveTo(230 * w, 0)
          ..quadraticBezierTo(260 * w, 140 * h, 390 * w, 180 * h)
          ..lineTo(390 * w, 0)
          ..close(),
        green);
    canvas.drawOval(Rect.fromLTWH(70 * w, 160 * h, 130 * w, 120 * h), light);
    canvas.drawPath(
        Path()
          ..moveTo(0, 290 * h)
          ..quadraticBezierTo(150 * w, 330 * h, 120 * w, 420 * h)
          ..quadraticBezierTo(90 * w, 480 * h, 0, 470 * h)
          ..close(),
        green);
    canvas.drawPath(
        Path()
          ..moveTo(240 * w, 140 * h)
          ..quadraticBezierTo(290 * w, 260 * h, 390 * w, 320 * h)
          ..lineTo(390 * w, 120 * h)
          ..close(),
        green);
    canvas.drawPath(
        Path()
          ..moveTo(175 * w, 480 * h)
          ..quadraticBezierTo(300 * w, 440 * h, 390 * w, 490 * h)
          ..lineTo(390 * w, 700 * h)
          ..quadraticBezierTo(250 * w, 620 * h, 170 * w, 560 * h)
          ..close(),
        green);
    canvas.drawOval(Rect.fromLTWH(140 * w, 20 * h, 100 * w, 60 * h), beige);
    canvas.drawOval(Rect.fromLTWH(330 * w, 560 * h, 90 * w, 60 * h), beige);
    canvas.drawOval(Rect.fromLTWH(40 * w, 580 * h, 80 * w, 80 * h), light);

    final road = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(
        Path()
          ..moveTo(0, 120 * h)
          ..quadraticBezierTo(180 * w, 100 * h, 300 * w, 180 * h)
          ..quadraticBezierTo(350 * w, 200 * h, 390 * w, 175 * h),
        road);
    canvas.drawPath(
        Path()
          ..moveTo(0, 410 * h)
          ..quadraticBezierTo(140 * w, 400 * h, 220 * w, 430 * h)
          ..quadraticBezierTo(320 * w, 380 * h, 390 * w, 420 * h),
        road);
    canvas.drawPath(
        Path()
          ..moveTo(70 * w, 0)
          ..quadraticBezierTo(60 * w, 300 * h, 100 * w, 420 * h)
          ..quadraticBezierTo(150 * w, 600 * h, 80 * w, 844 * h),
        road);
    canvas.drawPath(
        Path()
          ..moveTo(300 * w, 0)
          ..quadraticBezierTo(310 * w, 300 * h, 290 * w, 450 * h)
          ..quadraticBezierTo(270 * w, 650 * h, 300 * w, 844 * h),
        road);
    canvas.drawPath(
        Path()
          ..moveTo(150 * w, 250 * h)
          ..quadraticBezierTo(230 * w, 280 * h, 330 * w, 300 * h),
        road);
    canvas.drawPath(
        Path()
          ..moveTo(0, 640 * h)
          ..quadraticBezierTo(150 * w, 620 * h, 230 * w, 650 * h)
          ..quadraticBezierTo(320 * w, 680 * h, 390 * w, 640 * h),
        road);
    canvas.drawPath(
        Path()
          ..moveTo(0, 512 * h)
          ..quadraticBezierTo(150 * w, 530 * h, 220 * w, 510 * h)
          ..quadraticBezierTo(320 * w, 470 * h, 390 * w, 495 * h),
        Paint()
          ..color = const Color(0xFFA6CDE6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);

    // Trace : gris pour le reste du parcours, orange pour la partie faite.
    final trace = tracePath(size);
    canvas.drawPath(
      trace,
      Paint()
        ..color = const Color(0xFF7F8E86)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    final metric = trace.computeMetrics().first;
    final done = metric.extractPath(0, metric.length * userProgress);
    canvas.drawPath(
      done,
      Paint()
        ..color = const Color(0xFFFF6B1A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7,
    );
  }

  @override
  bool shouldRepaint(RaceMapPainter old) => old.userProgress != userProgress;
}
