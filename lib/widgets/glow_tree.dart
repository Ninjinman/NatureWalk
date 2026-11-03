import 'dart:math';
import 'package:flutter/material.dart';

/// DEEMO 風の、金色に光る大樹を描く。
/// [center] は幹の中心、[scale]=1 で高さ約 90px、[brightness] は 0〜1。
void paintGlowTree(
  Canvas canvas,
  Offset center, {
  double scale = 1,
  double brightness = 1,
  double t = 0,
}) {
  final b = brightness.clamp(0.0, 1.0);
  const gold = Color(0xFFE8B96A);

  // 背後の光
  final glowR = 70 * scale * (0.8 + 0.2 * sin(t * 1.2));
  canvas.drawCircle(
    center,
    glowR,
    Paint()
      ..shader = RadialGradient(
        colors: [gold.withValues(alpha: 0.35 * b), Colors.transparent],
      ).createShader(Rect.fromCircle(center: center, radius: glowR)),
  );

  // 幹
  final trunk = Path()
    ..moveTo(center.dx - 4 * scale, center.dy + 26 * scale)
    ..quadraticBezierTo(center.dx - 2 * scale, center.dy + 6 * scale,
        center.dx - 5 * scale, center.dy - 6 * scale)
    ..lineTo(center.dx + 5 * scale, center.dy - 6 * scale)
    ..quadraticBezierTo(center.dx + 2 * scale, center.dy + 6 * scale,
        center.dx + 4 * scale, center.dy + 26 * scale)
    ..close();
  canvas.drawPath(trunk, Paint()..color = const Color(0xFF2B2118));

  // 樹冠（重なる円）
  final crown = [
    Offset(0, -22), Offset(-14, -14), Offset(14, -14),
    Offset(-8, -30), Offset(9, -29), Offset(0, -10),
  ];
  for (var i = 0; i < crown.length; i++) {
    final o = center + crown[i] * scale;
    final r = (13 + (i % 3) * 2) * scale;
    canvas.drawCircle(
      o,
      r,
      Paint()
        ..color = Color.lerp(const Color(0xFF3A2D1A), gold, b)!
            .withValues(alpha: 0.55 + 0.25 * b)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale),
    );
  }

  // 舞い散る光の粒
  for (var i = 0; i < 6; i++) {
    final phase = i * 1.7;
    final a = (t * 0.4 + phase) % 1.0;
    final p = center + Offset(sin(phase * 3) * 24 * scale, -30 * scale + a * 50 * scale);
    canvas.drawCircle(p, 1.2 * scale,
        Paint()..color = gold.withValues(alpha: (1 - a) * 0.8 * b));
  }
}

/// ホーム画面などで使うウィジェット版
class GlowTree extends StatefulWidget {
  final double size;
  final double brightness;
  const GlowTree({super.key, this.size = 220, this.brightness = 1});

  @override
  State<GlowTree> createState() => _GlowTreeState();
}

class _GlowTreeState extends State<GlowTree> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _GlowTreePainter(widget.size / 90 * 0.9, widget.brightness, _c.value * 60),
      ),
    );
  }
}

class _GlowTreePainter extends CustomPainter {
  final double scale;
  final double brightness;
  final double t;
  _GlowTreePainter(this.scale, this.brightness, this.t);

  @override
  void paint(Canvas canvas, Size size) =>
      paintGlowTree(canvas, size.center(Offset.zero), scale: scale, brightness: brightness, t: t);

  @override
  bool shouldRepaint(covariant _GlowTreePainter old) => true;
}
