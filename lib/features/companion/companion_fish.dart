import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A chubby little fish that lives beside the page.
///
/// Drawn with a [CustomPainter] instead of a sprite so it can breathe, wag,
/// blink-ish and look at the pointer without any extra assets — and so the
/// spring-driven squash from [CompanionBody] bends it smoothly instead of
/// squashing a bitmap.
class CompanionFish extends StatelessWidget {
  const CompanionFish({
    super.key,
    required this.motion,
    required this.look,
    required this.bodyColor,
    required this.bellyColor,
    required this.finColor,
    required this.eyeColor,
  });

  /// Breathing phase in radians; the fish wags and swells with it.
  final ValueListenable<double> motion;

  /// Where the pointer is, normalised to -1..1 on both axes (0, 0 = centre).
  final ValueListenable<Offset> look;

  final Color bodyColor;
  final Color bellyColor;
  final Color finColor;
  final Color eyeColor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([motion, look]),
      builder: (context, _) => CustomPaint(
        painter: _FishPainter(
          phase: motion.value,
          look: look.value,
          bodyColor: bodyColor,
          bellyColor: bellyColor,
          finColor: finColor,
          eyeColor: eyeColor,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _FishPainter extends CustomPainter {
  const _FishPainter({
    required this.phase,
    required this.look,
    required this.bodyColor,
    required this.bellyColor,
    required this.finColor,
    required this.eyeColor,
  });

  final double phase;
  final Offset look;
  final Color bodyColor;
  final Color bellyColor;
  final Color finColor;
  final Color eyeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // The fish is a wide thing in a tall box: keep it near the bottom and let
    // the extra height be breathing room.
    final cx = w * 0.47;
    final cy = h * 0.66;
    final rx = w * 0.40 * (1 + math.sin(phase) * 0.03);
    final ry = h * 0.19 * (1 - math.sin(phase) * 0.03);
    final wag = math.sin(phase * 1.7);
    final flap = math.sin(phase * 1.7 + 1.1);

    _paintShadow(canvas, Offset(cx, cy + ry * 1.32), rx * 0.9);
    _paintTail(canvas, Offset(cx + rx * 0.86, cy), rx, ry, wag);
    _paintFins(canvas, Offset(cx, cy), rx, ry, flap);
    _paintBody(canvas, Offset(cx, cy), rx, ry);
    _paintFace(canvas, Offset(cx, cy), rx, ry);
  }

  void _paintShadow(Canvas canvas, Offset at, double rx) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(
      Rect.fromCenter(center: at, width: rx * 1.7, height: rx * 0.34),
      paint,
    );
  }

  void _paintTail(Canvas canvas, Offset at, double rx, double ry, double wag) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(wag * 0.22);
    final tail = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(rx * 0.55, -ry * 0.55, rx * 0.62, -ry * 0.05)
      ..quadraticBezierTo(rx * 0.64, ry * 0.12, rx * 0.56, ry * 0.5)
      ..quadraticBezierTo(rx * 0.2, ry * 0.45, 0, 0)
      ..close();
    canvas.drawPath(
      tail,
      Paint()..color = finColor.withValues(alpha: 0.92),
    );
    canvas.restore();
  }

  void _paintFins(Canvas canvas, Offset at, double rx, double ry, double flap) {
    final finPaint = Paint()..color = finColor.withValues(alpha: 0.9);

    // Side fin, waving.
    canvas.save();
    canvas.translate(at.dx - rx * 0.34, at.dy + ry * 0.30);
    canvas.rotate(-0.5 + flap * 0.18);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-rx * 0.02, ry * 0.18),
        width: rx * 0.42,
        height: ry * 0.46,
      ),
      finPaint,
    );
    canvas.restore();

    // Top fin, bobbing with the breath.
    canvas.save();
    canvas.translate(at.dx - rx * 0.04, at.dy - ry * 0.86);
    canvas.rotate(math.sin(phase) * 0.06 - 0.12);
    final top = Path()
      ..moveTo(-rx * 0.22, 0)
      ..quadraticBezierTo(-rx * 0.06, -ry * 0.62, rx * 0.20, -ry * 0.05)
      ..quadraticBezierTo(rx * 0.04, ry * 0.10, -rx * 0.22, 0)
      ..close();
    canvas.drawPath(top, finPaint);
    canvas.restore();
  }

  void _paintBody(Canvas canvas, Offset at, double rx, double ry) {
    final bodyRect = Rect.fromCenter(
      center: at,
      width: rx * 2,
      height: ry * 2,
    );
    final gradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(bodyColor, Colors.white, 0.22)!,
          bodyColor,
        ],
      ).createShader(bodyRect);
    canvas.drawOval(bodyRect, gradient);

    // Belly patch.
    final belly = Rect.fromCenter(
      center: at.translate(0, ry * 0.34),
      width: rx * 1.32,
      height: ry * 1.02,
    );
    canvas.drawOval(belly, Paint()..color = bellyColor.withValues(alpha: 0.95));

    // Soft rim so the blob reads against the page.
    canvas.drawOval(
      bodyRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, rx * 0.02)
        ..color = bodyColor.withValues(alpha: 0.55),
    );
  }

  void _paintFace(Canvas canvas, Offset at, double rx, double ry) {
    final eyeY = at.dy - ry * 0.18;
    final eyeX = rx * 0.30;
    final eyeR = math.min(rx * 0.19, ry * 0.34);
    final pupilShift = Offset(look.dx * eyeR * 0.30, look.dy * eyeR * 0.24);

    // Cheeks first, under the eyes.
    for (final side in const [-1, 1]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(at.dx + side * rx * 0.55, eyeY + ry * 0.34),
          width: rx * 0.30,
          height: ry * 0.26,
        ),
        Paint()..color = const Color(0xFFFF9BA8).withValues(alpha: 0.55),
      );
    }

    for (final side in const [-1, 1]) {
      final centre = Offset(at.dx + side * eyeX, eyeY);
      canvas.drawCircle(centre, eyeR, Paint()..color = Colors.white);
      canvas.drawCircle(
        centre + pupilShift,
        eyeR * 0.58,
        Paint()..color = eyeColor,
      );
      // Catch light.
      canvas.drawCircle(
        centre + pupilShift + Offset(-eyeR * 0.22, -eyeR * 0.24),
        eyeR * 0.20,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }

    // Mouth: a small content smile that widens when the fish is woken up.
    final smile = Path()
      ..moveTo(at.dx - rx * 0.14, at.dy + ry * 0.36)
      ..quadraticBezierTo(at.dx, at.dy + ry * 0.52, at.dx + rx * 0.14, at.dy + ry * 0.36);
    canvas.drawPath(
      smile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.2, rx * 0.035)
        ..color = eyeColor.withValues(alpha: 0.75),
    );
  }

  @override
  bool shouldRepaint(_FishPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.look != look ||
      oldDelegate.bodyColor != bodyColor ||
      oldDelegate.bellyColor != bellyColor ||
      oldDelegate.finColor != finColor ||
      oldDelegate.eyeColor != eyeColor;
}
