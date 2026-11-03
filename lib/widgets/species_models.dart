import 'dart:math';
import 'package:flutter/material.dart';
import '../models/creature.dart';

/// 生き物ごとの「立体モデル」を描く（写真は使わず、種の特徴を形・色・質感で表現する）。
///
/// すべて「足元を原点、1.0 = 1ワールド単位 = u ピクセル」の座標系で描く。
/// 右向きに描き、種ごとに左右反転して向きをばらけさせる。
///
/// 質感の方針:
///  - 葉・花は小さな葉の房を「明・中・暗」の3階調で重ね、下に落ち影を置く。
///  - 鳥は覆羽を段にして重ね、風切羽を尾の上へ伸ばす。
///  - 魚はうろこ・光沢・ひれの筋を重ねる。
class SpeciesRenderer {
  /// [ground] は足元の画面座標、[u] は 1 ワールド単位のピクセル数、
  /// [boost] は拡大表示で大きく見せる倍率。
  static void paint(Canvas canvas, Creature c, Offset ground, double u, double t,
      {double fit = 1, int pop = 10, double boost = 1}) {
    final seed = c.id.hashCode;
    final phase = (seed.abs() % 628) / 100.0;
    final dir = (seed >> 3).isEven ? 1.0 : -1.0;
    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.scale(dir * u * boost, u * boost);
    switch (c.type) {
      case CreatureType.plant:
        _plant(canvas, c.id, t, phase, fit, pop);
      case CreatureType.bird:
        _bird(canvas, c.id, t, phase);
      case CreatureType.fish:
        _fish(canvas, c.id, t, phase);
    }
    canvas.restore();
  }

  /// タップ判定・ラベル位置に使う、足元からの高さ（単位 u）と半径
  static double centerLift(Creature c) => switch (c.type) {
        CreatureType.plant => 0.13,
        CreatureType.bird => 0.07,
        CreatureType.fish => 0.03,
      };

  static double radius(Creature c) => switch (c.type) {
        CreatureType.plant => switch (c.id) {
            'sugi' || 'fuji' || 'sakura' || 'konara' || 'yamamo' || 'nemunoki' || 'ume' || 'icho' || 'momiji' || 'kusunoki' || 'buna' || 'kuromatsu' => 0.15,
            _ => 0.1,
          },
        CreatureType.bird => (c.id == 'aosagi' || c.id == 'daisagi' || c.id == 'tobi' || c.id == 'misago' || c.id == 'kawau') ? 0.13 : 0.08,
        CreatureType.fish => 0.07,
      };

  // ---------------------------------------------------------------------
  // 共通の描画部品
  // ---------------------------------------------------------------------

  static Paint _p(Color c) => Paint()..color = c;

  static Paint _stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..color = c;

  static Color _shade(Color c, double k) => Color.lerp(Colors.black, c, k)!;
  static Color _tint(Color c, double k) => Color.lerp(c, Colors.white, k)!;

  static void _shadow(Canvas c, double w, {double h = 0.5}) {
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: w, height: w * h),
        _p(Colors.black.withValues(alpha: 0.28)));
  }

  /// 陰影つきの球
  static void _ball(Canvas c, Offset p, double r, Color col, {double light = 0.3}) {
    c.drawCircle(
        p,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.45, -0.55),
            colors: [_tint(col, light), _shade(col, 0.55)],
          ).createShader(Rect.fromCircle(center: p, radius: r)));
  }

  /// 樹皮：ゆがんだ輪郭、縦に走る深い溝と明るい稜線、根元の苔
  static void _bark(Canvas c, double wBase, double wTop, double h,
      {Color col = const Color(0xFF4A3426), int seed = 1}) {
    final rng = Random(seed);
    final path = Path()..moveTo(-wBase * 1.7, 0);
    const n = 6;
    for (var i = 1; i <= n; i++) {
      final f = i / n;
      final w = wBase + (wTop - wBase) * f;
      path.lineTo(-w + (rng.nextDouble() - 0.5) * wBase * 0.4, -h * f);
    }
    path.lineTo(wTop, -h);
    for (var i = n - 1; i >= 1; i--) {
      final f = i / n;
      final w = wBase + (wTop - wBase) * f;
      path.lineTo(w + (rng.nextDouble() - 0.5) * wBase * 0.4, -h * f);
    }
    path.lineTo(wBase * 1.7, 0);
    path.close();
    c.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(colors: [_tint(col, 0.3), col, _shade(col, 0.55)])
              .createShader(Rect.fromLTWH(-wBase * 1.5, -h, wBase * 3, h)));
    // 樹皮の溝（暗）と稜線（明）
    c.save();
    c.clipPath(path);
    for (var i = 0; i < 12; i++) {
      final x = (rng.nextDouble() - 0.5) * (wBase + wTop) * 1.5;
      final y0 = -h * rng.nextDouble() * 0.3, y1 = -h * (0.5 + rng.nextDouble() * 0.5);
      final bend = (rng.nextDouble() - 0.5) * wBase * 0.8;
      final line = Path()
        ..moveTo(x, y0)
        ..quadraticBezierTo(x + bend, (y0 + y1) / 2, x + bend * 0.4, y1);
      c.drawPath(line, _stroke(_shade(col, 0.4).withValues(alpha: 0.75), 0.0032));
      c.drawPath(line.shift(const Offset(0.0028, 0)), _stroke(_tint(col, 0.35).withValues(alpha: 0.5), 0.0022));
    }
    // 節
    for (var i = 0; i < 2; i++) {
      final o = Offset((rng.nextDouble() - 0.5) * wBase, -h * (0.3 + rng.nextDouble() * 0.5));
      c.drawOval(Rect.fromCenter(center: o, width: wBase * 0.5, height: wBase * 0.34), _p(_shade(col, 0.45)));
    }
    c.restore();
    // 根元の苔
    for (var i = 0; i < 4; i++) {
      final x = -wBase * 1.3 + i * wBase * 0.5;
      c.drawOval(Rect.fromCenter(center: Offset(x, -h * 0.03 - rng.nextDouble() * h * 0.1), width: wBase * 1.1, height: wBase * 0.5),
          _p(Color.lerp(const Color(0xFF3F7A2E), const Color(0xFF9CC050), rng.nextDouble())!.withValues(alpha: 0.92)));
    }
  }

  /// 葉1枚（中肋つき）
  static void _leaf(Canvas c, Offset p, double len, double ang, Color col) {
    c.save();
    c.translate(p.dx, p.dy);
    c.rotate(ang);
    final path = Path()
      ..quadraticBezierTo(len * 0.45, -len * 0.4, len, 0)
      ..quadraticBezierTo(len * 0.45, len * 0.4, 0, 0);
    c.drawPath(path, _p(col));
    c.drawLine(Offset.zero, Offset(len * 0.92, 0), _stroke(_shade(col, 0.7), len * 0.04));
    c.restore();
  }

  /// 葉の房。落ち影の上に、明・中・暗の3階調の葉を重ねる。
  static void _foliage(Canvas c, Offset ctr, double rx, double ry, Color base,
      {int count = 80, double leaf = 0.03, int seed = 1, Color? accent, double accentP = 0}) {
    // 内側の暗がり（環境遮蔽）
    c.drawOval(Rect.fromCenter(center: ctr + Offset(rx * 0.06, ry * 0.12), width: rx * 2, height: ry * 2),
        _p(_shade(base, 0.38)));
    final rng = Random(seed);
    final pts = <(double, double, double, double)>[];
    for (var i = 0; i < count; i++) {
      final a = rng.nextDouble() * 2 * pi;
      final r = sqrt(rng.nextDouble());
      final x = cos(a) * r, y = sin(a) * r;
      final light = (0.5 - x * 0.28 - y * 0.42 + (rng.nextDouble() - 0.5) * 0.4).clamp(0.0, 1.0);
      pts.add((x, y, rng.nextDouble() * 2 * pi, light));
    }
    pts.sort((a, b) => a.$2.compareTo(b.$2));
    for (final p in pts) {
      final pos = Offset(ctr.dx + p.$1 * rx, ctr.dy + p.$2 * ry);
      if (accent != null && rng.nextDouble() < accentP) {
        _blossom(c, pos, leaf * 0.55, _tint(accent, (p.$4 - 0.5) * 0.3));
        continue;
      }
      final col = p.$4 < 0.34
          ? _shade(base, 0.62)
          : p.$4 < 0.67
              ? base
              : Color.lerp(_tint(base, 0.2), const Color(0xFFC8E070), 0.18)!;
      _leaf(c, pos, leaf * (0.8 + rng.nextDouble() * 0.5), p.$3, col);
    }
  }

  /// 5枚の花びらの小さな花（先端に切れ込み、付け根が濃く、おしべつき）
  static void _blossom(Canvas c, Offset p, double r, Color col) {
    for (var k = 0; k < 5; k++) {
      final a = k * 2 * pi / 5 - pi / 2 + 0.2;
      c.save();
      c.translate(p.dx, p.dy);
      c.rotate(a);
      final petal = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(r * 0.5, -r * 0.62, r * 1.18, -r * 0.3)
        ..lineTo(r * 1.04, 0)
        ..lineTo(r * 1.18, r * 0.3)
        ..quadraticBezierTo(r * 0.5, r * 0.62, 0, 0)
        ..close();
      c.drawPath(
          petal,
          Paint()
            ..shader = LinearGradient(colors: [_shade(col, 0.82), col, _tint(col, 0.25)])
                .createShader(Rect.fromLTWH(0, -r * 0.6, r * 1.2, r * 1.2)));
      c.restore();
    }
    c.drawCircle(p, r * 0.28, _p(_shade(col, 0.7)));
    for (var k = 0; k < 6; k++) {
      final a = k * pi / 3;
      final tip = p + Offset(cos(a), sin(a)) * r * 0.5;
      c.drawLine(p, tip, _stroke(const Color(0xFFF0E0A0), r * 0.07));
      c.drawCircle(tip, r * 0.07, _p(const Color(0xFFE8B84A)));
    }
  }

  /// 花の雲（サクラ）。明・中・暗の3階調のピンク
  static void _blossomCloud(Canvas c, Offset ctr, double rx, double ry,
      {int count = 70, double r = 0.016, int seed = 1}) {
    c.drawOval(Rect.fromCenter(center: ctr + Offset(rx * 0.05, ry * 0.1), width: rx * 2, height: ry * 2),
        _p(const Color(0xFFB8708A)));
    final rng = Random(seed);
    final pts = <(double, double, double)>[];
    for (var i = 0; i < count; i++) {
      final a = rng.nextDouble() * 2 * pi, rr = sqrt(rng.nextDouble());
      final x = cos(a) * rr, y = sin(a) * rr;
      pts.add((x, y, (0.5 - x * 0.28 - y * 0.42 + (rng.nextDouble() - 0.5) * 0.4).clamp(0.0, 1.0)));
    }
    pts.sort((a, b) => a.$2.compareTo(b.$2));
    for (final p in pts) {
      final col = p.$3 < 0.34
          ? const Color(0xFFDE8DA8)
          : p.$3 < 0.67
              ? const Color(0xFFF2B6C8)
              : const Color(0xFFFCE4EC);
      _blossom(c, Offset(ctr.dx + p.$1 * rx, ctr.dy + p.$2 * ry), r, col);
    }
  }

  // ---------------------------------------------------------------------
  // 植物
  // ---------------------------------------------------------------------

  static void _plant(Canvas c, String id, double t, double ph, double fit, int pop) {
    final grow = 0.78 + 0.22 * min(pop, 60) / 60;
    c.save();
    c.scale(grow, grow);
    _shadow(c, 0.18);
    switch (id) {
      case 'sakura': // 淡いピンクの花の雲と、舞う花びら
        _bark(c, 0.016, 0.01, 0.15, col: const Color(0xFF4A3830), seed: 3);
        for (final b in const [Offset(-0.07, -0.19), Offset(0.07, -0.19), Offset(0, -0.22)]) {
          c.drawLine(const Offset(0, -0.11), b, _stroke(const Color(0xFF4A3830), 0.01));
        }
        _blossomCloud(c, const Offset(0, -0.21), 0.12, 0.085, count: 80, r: 0.017, seed: 4);
        for (var k = 0; k < 7; k++) {
          final y = -0.04 - ((t * 0.04 + k * 0.15) % 1) * 0.22;
          c.save();
          c.translate(sin(t * 0.7 + k * 1.7) * 0.1, y);
          c.rotate(t * 0.8 + k);
          c.drawOval(Rect.fromCenter(center: Offset.zero, width: 0.014, height: 0.008), _p(const Color(0xFFF7B6C8)));
          c.restore();
        }
      case 'konara': // 太い幹と、どんぐりのついた広い樹冠
        _bark(c, 0.024, 0.016, 0.13, col: const Color(0xFF55402C), seed: 5);
        _foliage(c, const Offset(-0.05, -0.2), 0.09, 0.07, const Color(0xFF3F6B2E), count: 55, leaf: 0.034, seed: 6);
        _foliage(c, const Offset(0.06, -0.18), 0.09, 0.07, const Color(0xFF4A7A34), count: 55, leaf: 0.034, seed: 7);
        _foliage(c, const Offset(0.0, -0.25), 0.08, 0.06, const Color(0xFF55883A), count: 45, leaf: 0.034, seed: 8);
        for (final o in const [Offset(-0.06, -0.12), Offset(0.07, -0.11), Offset(0.0, -0.105), Offset(0.03, -0.13)]) {
          c.drawOval(Rect.fromCenter(center: o, width: 0.014, height: 0.019), _p(const Color(0xFF9A6A30)));
          c.drawArc(Rect.fromCenter(center: o - const Offset(0, 0.007), width: 0.017, height: 0.014),
              pi, pi, true, _p(const Color(0xFF5A3A1E)));
        }
      case 'sugi': // 細長い円錐形に重なった針葉樹（垂れた枝の層）
        _bark(c, 0.016, 0.012, 0.06, col: const Color(0xFF6A4A32), seed: 9);
        for (var i = 0; i < 5; i++) {
          final yb = -0.03 - i * 0.06;
          final hw = 0.105 - i * 0.02;
          final top = yb - 0.12;
          final tier = Path()
            ..moveTo(-hw, yb + 0.012)
            ..lineTo(0, top)
            ..lineTo(hw, yb + 0.012)
            ..close();
          c.drawPath(
              tier,
              Paint()
                ..shader = const LinearGradient(colors: [Color(0xFF5E9A56), Color(0xFF2F5E36), Color(0xFF1C3E26)])
                    .createShader(Rect.fromLTWH(-hw, top, hw * 2, yb - top)));
          // 垂れ下がる小枝（針葉の筋）
          for (var k = 1; k <= 9; k++) {
            final f = k / 9;
            final y = top + (yb - top) * f;
            final half = hw * f;
            for (final side in [-1.0, 1.0]) {
              c.drawLine(Offset(0, y - 0.01), Offset(side * half, y + 0.012),
                  _stroke(side < 0 ? const Color(0xFF6FAE60) : const Color(0xFF1F4A2A), 0.007));
            }
          }
        }
      case 'ajisai': // 大きな葉と、球状に集まった青・紫・ピンクの花
        for (final o in const [Offset(-0.08, -0.02), Offset(0.08, -0.025), Offset(0, -0.03), Offset(-0.05, -0.05), Offset(0.05, -0.055)]) {
          _leaf(c, Offset(o.dx, o.dy + 0.02), 0.08, o.dx < 0 ? pi + 0.5 : -0.5, const Color(0xFF3F7A34));
        }
        const cols = [Color(0xFF6E8BE0), Color(0xFF9C7BD8), Color(0xFFE58BB5), Color(0xFF7FA0E8)];
        const centers = [Offset(-0.06, -0.09), Offset(0.03, -0.125), Offset(0.075, -0.075), Offset(-0.005, -0.065)];
        for (var i = 0; i < 4; i++) {
          final rng = Random(i + 3);
          c.drawCircle(centers[i], 0.05, _p(_shade(cols[i], 0.5)));
          final pts = List.generate(26, (_) {
            final a = rng.nextDouble() * 2 * pi, r = sqrt(rng.nextDouble()) * 0.046;
            return Offset(cos(a) * r, sin(a) * r * 0.9);
          })..sort((a, b) => a.dy.compareTo(b.dy));
          for (final o in pts) {
            final l = (0.5 - o.dx * 6 - o.dy * 8).clamp(0.0, 1.0);
            _blossom(c, centers[i] + o, 0.013, l < 0.4 ? _shade(cols[i], 0.8) : l < 0.7 ? cols[i] : _tint(cols[i], 0.3));
          }
        }
      case 'tanpopo': // ギザギザの葉のロゼットと、黄色い花・綿毛
        for (var k = 0; k < 9; k++) {
          final a = -pi + k * pi / 8;
          _leaf(c, const Offset(0, -0.004), 0.085, a * 0.92, k.isEven ? const Color(0xFF4F8F3A) : const Color(0xFF3F7A30));
        }
        c.drawLine(const Offset(-0.035, -0.005), const Offset(-0.04, -0.1), _stroke(const Color(0xFF6E9A4A), 0.005));
        c.drawLine(const Offset(0.04, -0.005), const Offset(0.045, -0.13), _stroke(const Color(0xFF6E9A4A), 0.005));
        for (var layer = 0; layer < 2; layer++) {
          for (var k = 0; k < 18; k++) {
            final a = k * pi / 9 + layer * 0.17;
            c.drawLine(const Offset(-0.04, -0.105), Offset(-0.04 + cos(a) * (0.034 - layer * 0.01), -0.105 + sin(a) * (0.034 - layer * 0.01)),
                _stroke(layer == 0 ? const Color(0xFFF2C21A) : const Color(0xFFFFE05A), 0.006));
          }
        }
        for (var k = 0; k < 24; k++) {
          final a = k * pi / 12;
          c.drawLine(const Offset(0.045, -0.135), Offset(0.045 + cos(a) * 0.034, -0.135 + sin(a) * 0.034), _stroke(const Color(0xFFF4F4EE), 0.0035));
          c.drawCircle(Offset(0.045 + cos(a) * 0.034, -0.135 + sin(a) * 0.034), 0.0035, _p(Colors.white));
        }
        c.drawCircle(const Offset(0.045, -0.135), 0.008, _p(const Color(0xFFB0A890)));
      case 'shida': // 先端がくるりと巻いた若葉（ワラビ）
        for (var k = 0; k < 7; k++) {
          final a = -0.95 + k * 0.32;
          final tip = Offset(sin(a) * 0.1, -0.15 + cos(a) * 0.04 - (k % 2) * 0.02);
          c.drawPath(
              Path()
                ..moveTo(0, 0)
                ..quadraticBezierTo(sin(a) * 0.03, -0.1, tip.dx, tip.dy),
              _stroke(const Color(0xFF4F7F32), 0.011));
          for (var j = 1; j < 8; j++) {
            final f = j / 8;
            final p = Offset(tip.dx * f, tip.dy * f * 0.95 - 0.008);
            final len = 0.03 * (1 - f * 0.55);
            for (final s in [-1.0, 1.0]) {
              _leaf(c, p, len, s < 0 ? pi + 0.5 : -0.5, j.isEven ? const Color(0xFF6E9E48) : const Color(0xFF5E8F3A));
            }
          }
          c.drawCircle(tip, 0.012, _stroke(const Color(0xFF7DAE55), 0.005));
        }
      case 'nemunoki': // 傘のように広がる樹冠（羽状複葉）と、ピンクの花
        c.drawPath(
            Path()
              ..moveTo(0, 0)
              ..quadraticBezierTo(0.025, -0.08, -0.01, -0.16),
            _stroke(const Color(0xFF5A4630), 0.028));
        _foliage(c, const Offset(0, -0.17), 0.14, 0.04, const Color(0xFF4F8A3E), count: 70, leaf: 0.026, seed: 11);
        _foliage(c, const Offset(0, -0.2), 0.12, 0.035, const Color(0xFF5E9A4A), count: 60, leaf: 0.026, seed: 12);
        for (var k = 0; k < 10; k++) {
          final o = Offset(-0.11 + k * 0.024, -0.235 - (k % 3) * 0.011);
          for (var j = 0; j < 14; j++) {
            final a = j * pi / 7;
            c.drawLine(o, o + Offset(cos(a), sin(a)) * 0.03, _stroke(j.isEven ? const Color(0xFFF6B4C6) : const Color(0xFFF08AA8), 0.0035));
          }
          c.drawCircle(o, 0.008, _p(const Color(0xFFF8E0E6)));
        }
      case 'mangrove': // 水中に張り出す支柱根と、棒状の胎生種子
        c.drawOval(Rect.fromCenter(center: const Offset(0, 0.005), width: 0.24, height: 0.055),
            _stroke(Colors.white.withValues(alpha: 0.35), 0.003));
        for (var k = -4; k <= 4; k++) {
          if (k == 0) continue;
          final p = Path()
            ..moveTo(k * 0.005, -0.12)
            ..quadraticBezierTo(k * 0.05, -0.115, k * 0.065, 0);
          c.drawPath(p, _stroke(const Color(0xFF4A3220), 0.011));
          c.drawPath(p, _stroke(const Color(0xFF8A6844), 0.005));
        }
        _bark(c, 0.015, 0.012, 0.15, col: const Color(0xFF6A4A2A), seed: 13);
        _foliage(c, const Offset(0, -0.2), 0.085, 0.06, const Color(0xFF4F8F3A), count: 60, leaf: 0.034, seed: 14);
        _foliage(c, const Offset(-0.06, -0.17), 0.05, 0.04, const Color(0xFF3F7A2E), count: 30, leaf: 0.03, seed: 15);
        for (final x in const [-0.045, 0.0, 0.045]) {
          c.drawLine(Offset(x, -0.15), Offset(x, -0.07), _stroke(const Color(0xFF6E9A3A), 0.007));
          c.drawLine(Offset(x, -0.075), Offset(x, -0.065), _stroke(const Color(0xFF8A6A3A), 0.01));
        }
      case 'yamamo': // つややかな濃い緑と、粒々の赤い実
        _bark(c, 0.017, 0.012, 0.12, col: const Color(0xFF5A4636), seed: 16);
        _foliage(c, const Offset(0, -0.2), 0.1, 0.085, const Color(0xFF2F5A2A), count: 90, leaf: 0.034, seed: 17);
        final rng = Random(5);
        for (var k = 0; k < 22; k++) {
          final a = rng.nextDouble() * 2 * pi, r = sqrt(rng.nextDouble());
          final o = Offset(cos(a) * r * 0.1, -0.2 + sin(a) * r * 0.08);
          _ball(c, o, 0.0105, const Color(0xFFC0303E), light: 0.4);
          c.drawCircle(o - const Offset(0.003, 0.003), 0.0025, _p(Colors.white70));
        }
      case 'fuji': // 棚から垂れ下がる紫の房
        c.drawPath(
            Path()
              ..moveTo(-0.012, 0)
              ..quadraticBezierTo(0.035, -0.08, -0.02, -0.17),
            _stroke(const Color(0xFF4A3828), 0.026));
        c.drawPath(
            Path()
              ..moveTo(0.012, 0)
              ..quadraticBezierTo(-0.03, -0.09, 0.025, -0.17),
            _stroke(const Color(0xFF5E4834), 0.018));
        _foliage(c, const Offset(0, -0.195), 0.15, 0.032, const Color(0xFF6E9E48), count: 70, leaf: 0.028, seed: 18);
        for (var k = 0; k < 8; k++) {
          final x = -0.13 + k * 0.037;
          final sway = sin(t * 1.1 + k) * 0.007;
          for (var j = 0; j < 11; j++) {
            final f = j / 11;
            final r = 0.0125 * (1 - f * 0.6);
            final col = Color.lerp(const Color(0xFFCDB0F0), const Color(0xFF7E58C0), f)!;
            final p = Offset(x + sway * f + (j.isEven ? -0.004 : 0.004), -0.185 + j * 0.0155);
            _ball(c, p, r, col, light: 0.2);
          }
        }
      case 'suiren': // 水面の丸い葉（切れ込みと葉脈）と、とがった花びらの花
        for (final o in const [Offset(-0.075, 0.012), Offset(0.07, 0.016), Offset(0.0, 0.032)]) {
          final r = Rect.fromCenter(center: o, width: 0.105, height: 0.047);
          c.drawOval(r, _p(const Color(0xFF3F7F40)));
          c.drawOval(r.deflate(0.004), _p(const Color(0xFF5E9E52)));
          for (var k = 0; k < 7; k++) {
            final a = k * pi / 3.5;
            c.drawLine(o, o + Offset(cos(a) * 0.046, sin(a) * 0.02), _stroke(const Color(0xFF3F7F40), 0.002));
          }
          c.drawArc(r, 0.15, 0.5, true, _p(const Color(0xFF16394A)));
        }
        for (var layer = 0; layer < 2; layer++) {
          for (var k = 0; k < 8; k++) {
            final a = -pi + k * pi / 7;
            final sc = layer == 0 ? 1.0 : 0.65;
            c.drawPath(
                Path()
                  ..moveTo(0, -0.01)
                  ..lineTo(cos(a - 0.2) * 0.04 * sc, -0.01 + sin(a - 0.2) * 0.04 * sc)
                  ..lineTo(cos(a) * 0.066 * sc, -0.01 + sin(a) * 0.056 * sc)
                  ..lineTo(cos(a + 0.2) * 0.04 * sc, -0.01 + sin(a + 0.2) * 0.04 * sc)
                  ..close(),
                _p(Color.lerp(Colors.white, const Color(0xFFF4B6C2), k / 8 * (1 - layer * 0.4))!));
          }
        }
        c.drawCircle(const Offset(0, -0.015), 0.012, _p(const Color(0xFFFFD24A)));
      case 'hasu': // 高く伸びる茎、大きな盾形の葉、蓮の花と蜂の巣状の花托
        c.drawLine(const Offset(-0.05, 0), const Offset(-0.05, -0.14), _stroke(const Color(0xFF5E8F4A), 0.008));
        final leaf = Rect.fromCenter(center: const Offset(-0.05, -0.15), width: 0.18, height: 0.064);
        c.drawOval(leaf, _p(const Color(0xFF3F7F40)));
        c.drawOval(leaf.deflate(0.004), _p(const Color(0xFF5E9E58)));
        for (var k = 0; k < 10; k++) {
          final a = k * pi / 5;
          c.drawLine(const Offset(-0.05, -0.15), Offset(-0.05 + cos(a) * 0.085, -0.15 + sin(a) * 0.03), _stroke(const Color(0xFF3F7040), 0.003));
        }
        c.drawCircle(const Offset(-0.05, -0.152), 0.005, _p(Colors.white70));
        c.drawLine(const Offset(0.06, 0), const Offset(0.06, -0.22), _stroke(const Color(0xFF5E8F4A), 0.008));
        for (var layer = 0; layer < 2; layer++) {
          for (var k = 0; k < 9; k++) {
            final a = -pi + k * pi / 8 + layer * 0.17;
            c.save();
            c.translate(0.06, -0.225);
            c.rotate(a + pi / 2);
            c.drawOval(Rect.fromCenter(center: Offset(0, -0.035 + layer * 0.01), width: 0.036, height: 0.075 - layer * 0.02),
                _p(Color.lerp(const Color(0xFFF8D2DC), const Color(0xFFE0789C), k / 9 + layer * 0.15)!));
            c.restore();
          }
        }
        c.drawCircle(const Offset(0.06, -0.225), 0.013, _p(const Color(0xFFE8D060)));
        c.drawCircle(const Offset(0.06, -0.225), 0.006, _p(const Color(0xFF8A7A2A)));
      default:
        _plantExtra(c, id, t, ph);
    }
    c.restore();
  }

  // ---------------------------------------------------------------------
  // 追加した植物（共通の部品を組み合わせて描く）
  // ---------------------------------------------------------------------

  /// 広葉樹：樹皮のある幹と、明暗の葉の房。花や実を散らすこともできる
  static void _broadleaf(Canvas c, int seed,
      {required Color trunk,
      required Color crown,
      double rx = 0.1,
      double ry = 0.08,
      double h = 0.14,
      Color? accent,
      double accentP = 0,
      double leaf = 0.034,
      Color? second,
      Color? fruit}) {
    _bark(c, 0.018, 0.012, h, col: trunk, seed: seed);
    _foliage(c, Offset(-rx * 0.35, -h - ry * 0.55), rx * 0.8, ry * 0.85, second ?? _shade(crown, 0.9),
        count: 50, leaf: leaf, seed: seed + 1);
    _foliage(c, Offset(rx * 0.35, -h - ry * 0.45), rx * 0.8, ry * 0.85, crown,
        count: 50, leaf: leaf, seed: seed + 2);
    _foliage(c, Offset(0, -h - ry * 1.05), rx * 0.85, ry * 0.8, _tint(crown, 0.08),
        count: 55, leaf: leaf, seed: seed + 3, accent: accent, accentP: accentP);
    if (fruit != null) {
      final rng = Random(seed + 9);
      for (var k = 0; k < 14; k++) {
        final a = rng.nextDouble() * 2 * pi, r = sqrt(rng.nextDouble());
        final o = Offset(cos(a) * r * rx, -h - ry * 0.9 + sin(a) * r * ry);
        _ball(c, o, 0.01, fruit, light: 0.4);
      }
    }
  }

  static void _plantExtra(Canvas c, String id, double t, double ph) {
    switch (id) {
      case 'ume': // 白〜ピンクの花が、枝に直接咲く
        _broadleaf(c, 21,
            trunk: const Color(0xFF3F3028),
            crown: const Color(0xFFEBA6BA),
            accent: const Color(0xFFFFF6F6),
            accentP: 0.6,
            rx: 0.11,
            ry: 0.08,
            leaf: 0.03);
      case 'tsubaki': // つややかな濃い葉と、赤い花
        _shadow(c, 0.16);
        _foliage(c, const Offset(0, -0.07), 0.1, 0.065, const Color(0xFF1F4A2A), count: 80, leaf: 0.036, seed: 22);
        for (final o in const [Offset(-0.05, -0.1), Offset(0.04, -0.12), Offset(0.07, -0.06), Offset(-0.02, -0.05)]) {
          for (var layer = 0; layer < 2; layer++) {
            for (var k = 0; k < 6; k++) {
              final a = k * pi / 3 + layer * 0.5;
              _ball(c, o + Offset(cos(a), sin(a) * 0.8) * (0.016 - layer * 0.006), 0.012 - layer * 0.002,
                  layer == 0 ? const Color(0xFFC8283A) : const Color(0xFFE04A5A), light: 0.2);
            }
          }
          c.drawCircle(o, 0.008, _p(const Color(0xFFF2D24A)));
        }
      case 'ayame': // 剣のような葉と、紫の花
        for (var k = 0; k < 6; k++) {
          final x = -0.05 + k * 0.02;
          c.drawPath(
              Path()
                ..moveTo(x, 0)
                ..quadraticBezierTo(x + (k - 2.5) * 0.008, -0.09, x + (k - 2.5) * 0.014, -0.16 - (k % 2) * 0.02),
              _stroke(k.isEven ? const Color(0xFF4F8F3A) : const Color(0xFF3F7A30), 0.012));
        }
        for (final x in const [-0.02, 0.04]) {
          c.drawLine(Offset(x, 0), Offset(x, -0.19), _stroke(const Color(0xFF5E8F4A), 0.005));
          final f = Offset(x, -0.2);
          for (var k = 0; k < 3; k++) {
            final a = pi / 2 + (k - 1) * 1.1;
            c.drawOval(Rect.fromCenter(center: f + Offset(cos(a) * 0.022, sin(a) * 0.018), width: 0.034, height: 0.026),
                _p(k == 1 ? const Color(0xFF6A3FA8) : const Color(0xFF7E52BC)));
          }
          for (var k = 0; k < 3; k++) {
            final a = -pi / 2 + (k - 1) * 0.7;
            c.drawOval(Rect.fromCenter(center: f + Offset(cos(a) * 0.014, sin(a) * 0.016), width: 0.016, height: 0.028),
                _p(const Color(0xFF9A74D0)));
          }
          c.drawCircle(f + const Offset(0, 0.014), 0.005, _p(const Color(0xFFF2D24A)));
        }
      case 'susuki': // しなやかな葉と、銀白色の穂
        for (var k = 0; k < 16; k++) {
          final a = -1.0 + k * 0.13;
          c.drawPath(
              Path()
                ..moveTo(0, 0)
                ..quadraticBezierTo(sin(a) * 0.05, -0.12, sin(a) * 0.16, -0.12 + cos(a) * 0.05),
              _stroke(k.isEven ? const Color(0xFF8AAE55) : const Color(0xFF6E9440), 0.006));
        }
        for (var k = 0; k < 3; k++) {
          final x = -0.04 + k * 0.04;
          final tip = Offset(x + sin(t + k) * 0.006, -0.2 - (k % 2) * 0.03);
          c.drawLine(Offset(x * 0.3, 0), tip, _stroke(const Color(0xFF8A7A58), 0.004));
          for (var j = 0; j < 12; j++) {
            final f = j / 12;
            final b = Offset.lerp(tip + const Offset(0, 0.07), tip, f)!;
            c.drawLine(b, b + Offset(-0.03 * (1 - f * 0.5), -0.025), _stroke(const Color(0xFFE8E0C8).withValues(alpha: 0.9), 0.003));
            c.drawLine(b, b + Offset(0.03 * (1 - f * 0.5), -0.025), _stroke(const Color(0xFFD8CEB0).withValues(alpha: 0.9), 0.003));
          }
        }
      case 'higanbana': // 葉がなく、真っ赤な花が放射状に咲く
        for (var k = 0; k < 4; k++) {
          final x = -0.06 + k * 0.04;
          final tip = Offset(x + (k - 1.5) * 0.008, -0.15 - (k % 2) * 0.03);
          c.drawLine(Offset(x, 0), tip, _stroke(const Color(0xFF6E9A4A), 0.005));
          for (var j = 0; j < 7; j++) {
            final a = -pi * 0.85 + j * pi * 0.28;
            c.drawPath(
                Path()
                  ..moveTo(tip.dx, tip.dy)
                  ..quadraticBezierTo(tip.dx + cos(a) * 0.03, tip.dy + sin(a) * 0.035 - 0.015, tip.dx + cos(a) * 0.05, tip.dy + sin(a) * 0.04),
                _stroke(const Color(0xFFD8283A), 0.006));
            c.drawLine(tip, tip + Offset(cos(a) * 0.06, sin(a) * 0.05 - 0.01), _stroke(const Color(0xFFE85A5A), 0.0025));
            c.drawCircle(tip + Offset(cos(a) * 0.06, sin(a) * 0.05 - 0.01), 0.003, _p(const Color(0xFF3A1A1A)));
          }
        }
      case 'icho': // 扇形の葉が、黄色く色づく
        _broadleaf(c, 23,
            trunk: const Color(0xFF6A5A48),
            crown: const Color(0xFFC8C040),
            second: const Color(0xFFA8A02E),
            rx: 0.085,
            ry: 0.11,
            h: 0.15,
            leaf: 0.034);
      case 'momiji': // 手のひら状の葉が、赤く色づく
        _broadleaf(c, 24,
            trunk: const Color(0xFF55402C),
            crown: const Color(0xFFD8502A),
            second: const Color(0xFFB8381E),
            accent: const Color(0xFFE8902A),
            accentP: 0.0,
            rx: 0.11,
            ry: 0.08,
            leaf: 0.032);
      case 'kusunoki': // 大きくこんもり茂る、濃い緑の常緑樹
        _broadleaf(c, 25,
            trunk: const Color(0xFF55402C),
            crown: const Color(0xFF2A5A34),
            second: const Color(0xFF1C4A28),
            rx: 0.14,
            ry: 0.1,
            h: 0.12,
            leaf: 0.04);
      case 'buna': // 灰白色のなめらかな幹と、明るい緑の葉
        _broadleaf(c, 26,
            trunk: const Color(0xFF9A9486),
            crown: const Color(0xFF7DAE55),
            second: const Color(0xFF5E8F3A),
            rx: 0.11,
            ry: 0.09,
            h: 0.15,
            leaf: 0.034);
      case 'kuromatsu': // ねじれた幹と、雲のように広がる針葉の房
        _bark(c, 0.02, 0.014, 0.17, col: const Color(0xFF3F3028), seed: 27);
        c.drawLine(const Offset(0, -0.1), const Offset(-0.08, -0.17), _stroke(const Color(0xFF3F3028), 0.012));
        c.drawLine(const Offset(0, -0.13), const Offset(0.09, -0.2), _stroke(const Color(0xFF3F3028), 0.012));
        for (final o in const [Offset(-0.09, -0.19), Offset(0.1, -0.22), Offset(0, -0.26), Offset(-0.03, -0.16)]) {
          c.drawOval(Rect.fromCenter(center: o, width: 0.17, height: 0.07), _p(const Color(0xFF1F3E28)));
          final rng = Random((o.dx * 100).round() + 7);
          for (var k = 0; k < 44; k++) {
            final a = rng.nextDouble() * 2 * pi, r = sqrt(rng.nextDouble());
            final b = o + Offset(cos(a) * r * 0.07, sin(a) * r * 0.026);
            final ang = a + (rng.nextDouble() - 0.5) * 0.6;
            c.drawLine(b, b + Offset(cos(ang), sin(ang)) * 0.034,
                _stroke(k % 3 == 0 ? const Color(0xFF5E9A5A) : const Color(0xFF2F5A36), 0.0028));
          }
        }
      case 'gama': // 帯状の葉と、茶色いソーセージ形の穂
        for (var k = 0; k < 6; k++) {
          final x = -0.05 + k * 0.02;
          c.drawPath(
              Path()
                ..moveTo(x, 0)
                ..quadraticBezierTo(x + (k - 2.5) * 0.01, -0.1, x + (k - 2.5) * 0.03, -0.18),
              _stroke(k.isEven ? const Color(0xFF6E9E48) : const Color(0xFF5E8F3A), 0.011));
        }
        for (final x in const [-0.012, 0.03]) {
          c.drawLine(Offset(x, 0), Offset(x, -0.2), _stroke(const Color(0xFF6E8A4A), 0.005));
          c.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(x - 0.009, -0.215, 0.018, 0.07), const Radius.circular(0.009)),
              _p(const Color(0xFF6A4A2A)));
          c.drawLine(Offset(x, -0.215), Offset(x, -0.245), _stroke(const Color(0xFFB89A5A), 0.003));
        }
      case 'yoshi': // 高く伸びる茎と、ふさふさした穂
        for (var k = 0; k < 5; k++) {
          final x = -0.05 + k * 0.025;
          final tip = Offset(x + sin(t * 0.8 + k) * 0.006 + (k - 2) * 0.012, -0.24 - (k % 2) * 0.03);
          c.drawPath(
              Path()
                ..moveTo(x, 0)
                ..quadraticBezierTo(x, -0.12, tip.dx, tip.dy),
              _stroke(const Color(0xFF9A9A5A), 0.005));
          for (var j = 0; j < 10; j++) {
            final f = j / 10;
            final b = Offset.lerp(tip + const Offset(0, 0.07), tip, f)!;
            c.drawLine(b, b + Offset(-0.022, -0.02), _stroke(const Color(0xFFC8B890).withValues(alpha: 0.9), 0.0028));
            c.drawLine(b, b + Offset(0.022, -0.02), _stroke(const Color(0xFFB8A880).withValues(alpha: 0.9), 0.0028));
          }
          for (var j = 0; j < 3; j++) {
            _leaf(c, Offset(x, -0.04 - j * 0.04), 0.06, k.isEven ? -0.6 : pi + 0.6, const Color(0xFF7DAE55));
          }
        }
      case 'kohone': // 水面の細長い葉と、黄色い花
        for (final o in const [Offset(-0.075, 0.012), Offset(0.07, 0.016)]) {
          final r = Rect.fromCenter(center: o, width: 0.11, height: 0.04);
          c.drawOval(r, _p(const Color(0xFF3F7F40)));
          c.drawOval(r.deflate(0.004), _p(const Color(0xFF5E9E52)));
        }
        c.drawLine(const Offset(0, 0.01), const Offset(0, -0.1), _stroke(const Color(0xFF5E8F4A), 0.006));
        for (var layer = 0; layer < 2; layer++) {
          for (var k = 0; k < 5; k++) {
            final a = -pi + k * pi / 4;
            _ball(c, Offset(cos(a) * (0.022 - layer * 0.008), -0.105 + sin(a) * (0.018 - layer * 0.006)),
                0.017 - layer * 0.004, layer == 0 ? const Color(0xFFF2C21A) : const Color(0xFFF8DC5A), light: 0.2);
          }
        }
        c.drawCircle(const Offset(0, -0.105), 0.008, _p(const Color(0xFFD88A2A)));
      case 'haimatsu': // 地面を這い、雲のように広がる針葉と、小さな赤紫の松かさ
        c.drawPath(
            Path()
              ..moveTo(-0.1, -0.005)
              ..quadraticBezierTo(-0.02, -0.03, 0.1, -0.01),
            _stroke(const Color(0xFF4A3A30), 0.012));
        for (final o in const [Offset(-0.07, -0.04), Offset(0.0, -0.06), Offset(0.07, -0.04), Offset(-0.03, -0.025), Offset(0.04, -0.03)]) {
          c.drawOval(Rect.fromCenter(center: o, width: 0.11, height: 0.045), _p(const Color(0xFF1F3E28)));
          final rng = Random((o.dx * 100).round() + 11);
          for (var k = 0; k < 34; k++) {
            final a = rng.nextDouble() * 2 * pi, r = sqrt(rng.nextDouble());
            final b = o + Offset(cos(a) * r * 0.05, sin(a) * r * 0.018);
            final ang = a + (rng.nextDouble() - 0.5) * 0.6;
            c.drawLine(b, b + Offset(cos(ang), sin(ang)) * 0.03,
                _stroke(k % 3 == 0 ? const Color(0xFF5E9A5A) : const Color(0xFF2F5A36), 0.0026));
          }
        }
        for (final o in const [Offset(-0.05, -0.07), Offset(0.05, -0.065)]) {
          c.drawOval(Rect.fromCenter(center: o, width: 0.014, height: 0.02), _p(const Color(0xFF8A3A5A)));
        }
      case 'komakusa': // 粉をふいたような灰緑の葉と、ハート形のピンクの花
        for (var k = 0; k < 9; k++) {
          final a = -pi + k * pi / 8;
          final tip = Offset(cos(a) * 0.075, -0.004 + sin(a) * 0.035);
          c.drawLine(const Offset(0, -0.003), tip, _stroke(const Color(0xFF8AA89A), 0.007));
          for (var j = 1; j < 4; j++) {
            final p = Offset.lerp(const Offset(0, -0.003), tip, j / 4)!;
            c.drawLine(p, p + Offset(0, -0.014), _stroke(const Color(0xFFA8C0B0), 0.0035));
          }
        }
        for (final x in const [-0.03, 0.012, 0.045]) {
          final top = Offset(x, -0.11 - (x * 100).abs() * 0.001);
          c.drawPath(
              Path()
                ..moveTo(x * 0.5, -0.004)
                ..quadraticBezierTo(x, -0.07, top.dx, top.dy),
              _stroke(const Color(0xFF8AA89A), 0.004));
          _ball(c, top + const Offset(-0.008, 0.012), 0.012, const Color(0xFFE8789C), light: 0.3);
          _ball(c, top + const Offset(0.008, 0.012), 0.012, const Color(0xFFE8789C), light: 0.3);
          c.drawCircle(top + const Offset(0, 0.028), 0.006, _p(const Color(0xFFF8E8EC)));
        }
      case 'shirabiso': // 青みがかった緑の細長い円錐形
        _bark(c, 0.012, 0.009, 0.05, col: const Color(0xFF8A8A84), seed: 31);
        for (var i = 0; i < 7; i++) {
          final yb = -0.03 - i * 0.05;
          final hw = 0.085 - i * 0.011;
          final top = yb - 0.1;
          final tier = Path()
            ..moveTo(-hw, yb + 0.01)
            ..lineTo(0, top)
            ..lineTo(hw, yb + 0.01)
            ..close();
          c.drawPath(
              tier,
              Paint()
                ..shader = const LinearGradient(colors: [Color(0xFF5E9A8A), Color(0xFF2A5A4A), Color(0xFF1C3E34)])
                    .createShader(Rect.fromLTWH(-hw, top, hw * 2, yb - top)));
          for (var k = 1; k <= 8; k++) {
            final f = k / 8;
            final y = top + (yb - top) * f;
            final half = hw * f;
            for (final side in [-1.0, 1.0]) {
              c.drawLine(Offset(0, y - 0.008), Offset(side * half, y + 0.01),
                  _stroke(side < 0 ? const Color(0xFF7CB0A0) : const Color(0xFF1F4A3A), 0.0065));
            }
          }
        }
        for (final o in const [Offset(-0.012, -0.355), Offset(0.014, -0.34)]) {
          c.drawOval(Rect.fromCenter(center: o, width: 0.011, height: 0.026), _p(const Color(0xFF6A4A8A)));
        }
      case 'nikkokisuge': // 弓なりの細い葉と、オレンジがかった黄色のラッパ形の花
        for (var k = 0; k < 9; k++) {
          final a = -1.1 + k * 0.28;
          c.drawPath(
              Path()
                ..moveTo(0, 0)
                ..quadraticBezierTo(sin(a) * 0.05, -0.1, sin(a) * 0.15, -0.09 + cos(a) * 0.04),
              _stroke(k.isEven ? const Color(0xFF7DAE55) : const Color(0xFF5E9040), 0.006));
        }
        for (final x in const [-0.035, 0.01, 0.05]) {
          final top = Offset(x * 1.2, -0.17 - (x > 0 ? 0.02 : 0.0));
          c.drawLine(Offset(x * 0.4, -0.005), top, _stroke(const Color(0xFF6E9A4A), 0.005));
          for (var k = 0; k < 6; k++) {
            final a = k * pi / 3 - pi / 2;
            c.save();
            c.translate(top.dx, top.dy);
            c.rotate(a);
            c.drawOval(Rect.fromCenter(center: const Offset(0, -0.026), width: 0.024, height: 0.06),
                _p(Color.lerp(const Color(0xFFF2A82A), const Color(0xFFF8C84A), k / 6)!));
            c.restore();
          }
          c.drawCircle(top, 0.008, _p(const Color(0xFFE8902A)));
        }
      case 'amamo': // 海中でゆらめくリボン状の葉
        for (var k = 0; k < 10; k++) {
          final x = -0.07 + k * 0.016;
          final sw = sin(t * 1.4 + k * 0.7) * 0.02;
          final p = Path()
            ..moveTo(x, 0)
            ..quadraticBezierTo(x + sw * 0.5, -0.07, x + sw, -0.15 - (k % 3) * 0.03);
          c.drawPath(p, _stroke(const Color(0xFF3F8F5A).withValues(alpha: 0.9), 0.012));
          c.drawPath(p, _stroke(const Color(0xFF7DCE8A).withValues(alpha: 0.5), 0.004));
        }
      default:
        _genericPlant(c, id, t, ph);
    }
  }


  // ---------------------------------------------------------------------
  // 追加植物の汎用モデル（種類・色・大きさの指定から描く）
  //   指定: 種類|色1|色2|色3|大きさ|形
  // ---------------------------------------------------------------------

  static Color _hex(String s, Color fallback) {
    if (s.length != 6) return fallback;
    final v = int.tryParse(s, radix: 16);
    return v == null ? fallback : Color(0xFF000000 | v);
  }

  static void _genericPlant(Canvas c, String id, double t, double ph) {
    final spec = _genericPlants[id];
    if (spec == null) {
      _ball(c, const Offset(0, -0.1), 0.07, const Color(0xFF4F8F3A));
      return;
    }
    final f = spec.split('|');
    final kind = f[0];
    final c1 = _hex(f[1], const Color(0xFF4F8F3A));
    final c2 = _hex(f[2], const Color(0xFF4F8F3A));
    final c3 = f.length > 3 ? _hex(f[3], const Color(0xFFFFFFFF)) : const Color(0xFFFFFFFF);
    final k = f.length > 4 ? (double.tryParse(f[4]) ?? 1.0) : 1.0;
    final seed = id.hashCode & 0xFFFF;
    final rng = Random(seed);
    switch (kind) {
      case 'tree':
      case 'treeB':
      case 'treeF':
        final h = 0.15 * k, rx = 0.1 * k, ry = 0.08 * k;
        _broadleaf(c, seed,
            trunk: c1,
            crown: c2,
            rx: rx,
            ry: ry,
            h: h,
            accent: kind == 'treeB' ? c3 : null,
            accentP: kind == 'treeB' ? 0.55 : 0,
            fruit: kind == 'treeF' ? c3 : null);
      case 'conifer':
        final yb = -0.02;
        for (var i = 0; i < 4; i++) {
          final hw = (0.1 - i * 0.02) * k;
          final top = (yb - 0.1 * (i + 1) * k) * 1.0;
          final base = yb - 0.07 * i * k;
          final tier = Path()
            ..moveTo(-hw, base)
            ..lineTo(0, top)
            ..lineTo(hw, base)
            ..close();
          c.drawPath(
              tier,
              Paint()
                ..shader = LinearGradient(colors: [c2, c1, _shade(c1, 0.7)])
                    .createShader(Rect.fromLTWH(-hw, top, hw * 2, base - top)));
        }
        c.drawLine(const Offset(0, 0), Offset(0, yb), _stroke(const Color(0xFF4A3426), 0.02));
      case 'pine':
        _bark(c, 0.016, 0.01, 0.22 * k, col: c2, seed: seed);
        for (var i = 0; i < 3; i++) {
          _foliage(c, Offset((i - 1) * 0.07 * k, -0.2 * k - (i == 1 ? 0.04 : 0)), 0.08 * k, 0.04 * k, c1,
              count: 40, leaf: 0.03, seed: seed + i);
        }
      case 'shrub':
      case 'shrubF':
        if (kind == 'shrub') _bark(c, 0.012, 0.01, 0.07 * k, col: c1, seed: seed);
        _shadow(c, 0.14 * k);
        _foliage(c, Offset(0, -0.09 * k), 0.09 * k, 0.065 * k, c2,
            count: 70, leaf: 0.03, seed: seed + 1, accent: c3, accentP: 0.35);
        if (kind == 'shrubF') {
          for (var j = 0; j < 8; j++) {
            _ball(c, Offset((rng.nextDouble() - 0.5) * 0.14 * k, -0.06 * k - rng.nextDouble() * 0.08 * k), 0.01, c3,
                light: 0.4);
          }
        }
      case 'herb':
        for (var j = 0; j < 4; j++) {
          final x = -0.05 + j * 0.033;
          final top = -0.1 * k - (j % 2) * 0.03;
          _leaf(c, Offset(x, 0), 0.07 * k, -pi / 2 + (j - 1.5) * 0.45, c2);
          c.drawLine(Offset(x, 0), Offset(x * 1.2, top), _stroke(_shade(c2, 0.9), 0.006));
          final ctr = Offset(x * 1.2, top);
          for (var m = 0; m < 5; m++) {
            final a = m * 2 * pi / 5 + j;
            _ball(c, ctr + Offset(cos(a), sin(a) * 0.8) * 0.014, 0.011, c1, light: 0.25);
          }
          _ball(c, ctr, 0.007, c3, light: 0.2);
        }
      case 'spike':
        for (var j = 0; j < 5; j++) {
          final x = -0.06 + j * 0.03;
          final top = -0.15 * k - (j % 2) * 0.04;
          final sw = sin(t * 1.2 + j) * 0.004;
          c.drawLine(Offset(x, 0), Offset(x + sw, top), _stroke(c2, 0.007));
          for (var m = 0; m < 6; m++) {
            _ball(c, Offset(x + sw, top + m * 0.012), 0.011 - m * 0.001, c1, light: 0.25);
          }
        }
      case 'grass':
        for (var j = 0; j < 9; j++) {
          final x = -0.07 + j * 0.0175;
          final sw = sin(t * 1.5 + j * 0.6) * 0.012;
          final p = Path()
            ..moveTo(x, 0)
            ..quadraticBezierTo(x + sw * 0.5, -0.08 * k, x + (j - 4) * 0.01 + sw, -0.15 * k - (j % 3) * 0.025);
          c.drawPath(p, _stroke(j.isEven ? c1 : _shade(c1, 0.8), 0.011));
        }
      case 'floating':
        for (var j = 0; j < 5; j++) {
          final o = Offset((rng.nextDouble() - 0.5) * 0.14, (rng.nextDouble() - 0.5) * 0.05 - 0.02);
          c.drawOval(Rect.fromCenter(center: o, width: 0.07 * k, height: 0.035 * k), _p(c1));
          c.drawOval(Rect.fromCenter(center: o + const Offset(-0.005, -0.004), width: 0.04 * k, height: 0.018 * k),
              _p(_tint(c1, 0.2)));
        }
        if (f[2] != '-') _ball(c, const Offset(0.02, -0.04), 0.016, c2, light: 0.3);
      case 'seaweed':
        for (var j = 0; j < 6; j++) {
          final x = -0.06 + j * 0.024;
          final sw = sin(t * 1.4 + j * 0.8) * 0.025;
          final p = Path()
            ..moveTo(x, 0)
            ..quadraticBezierTo(x + sw * 0.5, -0.08 * k, x + sw, -0.16 * k - (j % 3) * 0.03 * k);
          c.drawPath(p, _stroke(c1.withValues(alpha: 0.92), 0.018));
          c.drawPath(p, _stroke(_tint(c1, 0.3).withValues(alpha: 0.5), 0.005));
        }
      default:
        _ball(c, const Offset(0, -0.1), 0.07, c1);
    }
  }

  // ---------------------------------------------------------------------
  // 鳥
  // ---------------------------------------------------------------------

  static void _bird(Canvas c, String id, double t, double ph) {
    final s = _birdSpecs[id] ?? _birdSpecs['suzume']!;
    final L = s.len;
    final flap = sin(t * 7 + ph);
    c.save();
    c.translate(0, sin(t * 2 + ph) * 0.004);

    final bcY = -(s.leg + L * 0.32);

    if (s.floating) {
      for (var i = 0; i < 2; i++) {
        c.drawOval(Rect.fromCenter(center: const Offset(0, 0.0), width: L * (1.5 + i * 0.4), height: L * (0.4 + i * 0.1)),
            _stroke(Colors.white.withValues(alpha: 0.4 - i * 0.15), 0.003));
      }
    } else {
      // 脚と足指
      final lp = _stroke(s.legColor, 0.0055);
      for (final x in [-L * 0.05, L * 0.09]) {
        c.drawLine(Offset(x, bcY + L * 0.2), Offset(x + 0.002, 0), lp);
        for (final dx in [-L * 0.1, 0.0, L * 0.1]) {
          c.drawLine(Offset(x + 0.002, 0), Offset(x + 0.002 + dx + L * 0.05, 0.0), lp);
        }
      }
    }

    // 尾羽（2枚重ね）
    final tailBase = Offset(-L * 0.42, bcY - L * 0.02);
    for (var i = 0; i < 2; i++) {
      final off = i * L * 0.04;
      final tail = Path()..moveTo(tailBase.dx, tailBase.dy - L * 0.08 + off);
      if (s.fork) {
        tail
          ..lineTo(tailBase.dx - s.tail, tailBase.dy - L * 0.14 + off)
          ..lineTo(tailBase.dx - s.tail * 0.55, tailBase.dy + L * 0.02)
          ..lineTo(tailBase.dx - s.tail, tailBase.dy + L * 0.16 - off)
          ..lineTo(tailBase.dx, tailBase.dy + L * 0.08);
      } else {
        tail
          ..lineTo(tailBase.dx - s.tail * (1 - i * 0.06), tailBase.dy - L * 0.03 + off)
          ..lineTo(tailBase.dx - s.tail * (1 - i * 0.06), tailBase.dy + L * 0.07 - off)
          ..lineTo(tailBase.dx, tailBase.dy + L * 0.08);
      }
      tail.close();
      c.drawPath(tail, _p(i == 0 ? _shade(s.tailColor, 0.8) : s.tailColor));
    }

    // 首（サギなど）
    final hr = L * s.headR;
    final hc = Offset(L * 0.4, bcY - L * 0.16 - s.neck);
    if (s.neck > 0) {
      final neck = Path()
        ..moveTo(L * 0.28, bcY - L * 0.1)
        ..quadraticBezierTo(L * 0.1, bcY - s.neck * 0.7, hc.dx - hr * 0.2, hc.dy + hr * 0.4);
      c.drawPath(neck, _stroke(_shade(s.neckColor, 0.8), L * 0.13));
      c.drawPath(neck, _stroke(s.neckColor, L * 0.1));
    }

    // 胴体（くちばし側が胸、尾側が細くなるしずく形）
    final body = Path()
      ..moveTo(L * 0.46, bcY - L * 0.02)
      ..cubicTo(L * 0.5, bcY - L * 0.3, L * 0.15, bcY - L * 0.34, -L * 0.2, bcY - L * 0.3)
      ..cubicTo(-L * 0.4, bcY - L * 0.26, -L * 0.5, bcY - L * 0.12, -L * 0.52, bcY - L * 0.06)
      ..cubicTo(-L * 0.4, bcY + L * 0.1, -L * 0.05, bcY + L * 0.34, L * 0.25, bcY + L * 0.3)
      ..cubicTo(L * 0.42, bcY + L * 0.26, L * 0.5, bcY + L * 0.15, L * 0.46, bcY - L * 0.02)
      ..close();
    final bodyRect = Rect.fromLTRB(-L * 0.52, bcY - L * 0.34, L * 0.5, bcY + L * 0.34);
    c.drawPath(
        body,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_shade(s.back, 0.85), s.back, s.back, s.belly, _shade(s.belly, 0.85)],
            stops: const [0, 0.2, 0.42, 0.62, 1],
          ).createShader(bodyRect));
    // 羽毛の質感（小さな鱗状の弧を段にして重ねる）
    c.save();
    c.clipPath(body);
    for (var row = 0; row < 6; row++) {
      for (var k = 0; k < 9; k++) {
        final x = -L * 0.46 + k * L * 0.115 + (row.isOdd ? L * 0.055 : 0);
        final y = bcY - L * 0.22 + row * L * 0.1;
        c.drawArc(Rect.fromCenter(center: Offset(x, y), width: L * 0.1, height: L * 0.08), 0.1, pi * 0.8, false,
            _stroke(Colors.black.withValues(alpha: row < 3 ? 0.13 : 0.07), 0.0022));
      }
    }
    // 腹側の光の回り込み
    c.drawOval(Rect.fromCenter(center: Offset(L * 0.1, bcY + L * 0.22), width: L * 0.9, height: L * 0.18),
        _p(Colors.white.withValues(alpha: 0.12)));
    c.restore();

    // 翼：覆羽を3段に重ね、風切羽を尾の上へ伸ばす
    c.save();
    c.translate(L * 0.1, bcY - L * 0.06);
    c.rotate(-0.08 + flap * 0.1);
    final wl = L * s.wingLen;
    for (var i = 0; i < 4; i++) {
      final f = i / 3;
      c.drawPath(
          Path()
            ..moveTo(-wl * 0.15, L * (0.03 + i * 0.02))
            ..quadraticBezierTo(-wl * 0.55, L * (0.1 + i * 0.012), -wl * (0.85 + f * 0.25), L * (0.04 + i * 0.035)),
          _stroke(_shade(s.wing, 0.55 + f * 0.15), L * 0.055));
    }
    final wing = Path()
      ..moveTo(wl * 0.08, -L * 0.08)
      ..quadraticBezierTo(-wl * 0.35, -L * 0.2, -wl * 0.72, -L * 0.02)
      ..quadraticBezierTo(-wl * 0.4, L * 0.16, wl * 0.05, L * 0.1)
      ..close();
    c.drawPath(
        wing,
        Paint()
          ..shader = LinearGradient(colors: [_tint(s.wing, 0.12), _shade(s.wing, 0.78)])
              .createShader(Rect.fromLTWH(-wl * 0.75, -L * 0.2, wl * 0.85, L * 0.35)));
    for (var row = 0; row < 3; row++) {
      for (var k = 0; k < 5 - row; k++) {
        c.drawArc(
            Rect.fromCenter(center: Offset(-wl * 0.05 - k * wl * 0.14 - row * wl * 0.04, -L * 0.04 + row * L * 0.05), width: wl * 0.17, height: L * 0.1),
            0.2, pi * 0.7, false, _stroke(_shade(s.wing, 0.5).withValues(alpha: 0.55), 0.0028));
      }
    }
    if (s.wingBars) {
      for (final x in [-0.12, -0.24]) {
        c.drawLine(Offset(L * x, -L * 0.1), Offset(L * x, L * 0.1), _stroke(Colors.black87, 0.0055));
      }
    }
    c.restore();

    // 頭（球面のグラデーション）
    c.drawCircle(
        hc,
        hr,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.5),
            colors: [_tint(s.head, 0.25), s.head, _shade(s.head, 0.7)],
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromCircle(center: hc, radius: hr)));

    // 嘴（上下2色の陰影つき）
    final beakTop = Path()
      ..moveTo(hc.dx + hr * 0.7, hc.dy - hr * 0.25)
      ..lineTo(hc.dx + hr * 0.7 + L * s.beakLen, hc.dy + hr * 0.05)
      ..lineTo(hc.dx + hr * 0.7, hc.dy + hr * 0.05)
      ..close();
    final beakBottom = Path()
      ..moveTo(hc.dx + hr * 0.7, hc.dy + hr * 0.05)
      ..lineTo(hc.dx + hr * 0.7 + L * s.beakLen * 0.92, hc.dy + hr * 0.06)
      ..lineTo(hc.dx + hr * 0.7, hc.dy + hr * 0.32)
      ..close();
    c.drawPath(beakTop, _p(s.beak));
    c.drawPath(beakBottom, _p(_shade(s.beak, 0.75)));
    c.drawCircle(Offset(hc.dx + hr * 0.85, hc.dy - hr * 0.1), hr * 0.04, _p(Colors.black45));

    // 種ごとの特徴
    _birdMarks(c, id, L, Offset(0, bcY), hc, hr, s);

    // 目（リングとハイライト）
    final eye = Offset(hc.dx + hr * 0.3, hc.dy - hr * 0.15);
    c.drawCircle(eye, hr * 0.24, _p(Colors.black.withValues(alpha: 0.35)));
    c.drawCircle(eye, hr * 0.17, _p(Colors.black));
    c.drawCircle(eye + Offset(hr * 0.05, -hr * 0.06), hr * 0.055, _p(Colors.white));
    c.restore();
  }

  static void _birdMarks(Canvas c, String id, double L, Offset bc, Offset hc, double hr, _B s) {
    switch (id) {
      case 'uguisu':
        c.drawLine(hc + Offset(-hr * 0.1, -hr * 0.35), hc + Offset(hr * 0.9, -hr * 0.3), _stroke(const Color(0xFFE8E0C0), 0.006));
      case 'mejiro':
        c.drawCircle(hc + Offset(hr * 0.3, -hr * 0.15), hr * 0.32, _stroke(Colors.white, 0.006));
        c.drawCircle(hc + Offset(hr * 0.25, hr * 0.6), hr * 0.35, _p(const Color(0xFFE8D84A)));
      case 'joubitaki':
        c.drawOval(Rect.fromCenter(center: Offset(-L * 0.05, bc.dy - L * 0.08), width: L * 0.18, height: L * 0.12), _p(Colors.white));
      case 'kisekirei':
        c.drawLine(hc + Offset(-hr * 0.3, -hr * 0.45), hc + Offset(hr * 0.7, -hr * 0.35), _stroke(Colors.white, 0.005));
      case 'hakusekirei':
        c.drawLine(hc + Offset(-hr * 0.2, -hr * 0.1), hc + Offset(hr * 0.7, -hr * 0.1), _stroke(Colors.black87, 0.005));
        c.drawOval(Rect.fromCenter(center: hc + Offset(-hr * 0.1, hr * 1.1), width: hr * 1.3, height: hr * 0.8), _p(Colors.black87));
      case 'kawau':
        c.drawCircle(hc + Offset(hr * 0.7, hr * 0.5), hr * 0.3, _p(const Color(0xFFF2D84A)));
        c.drawCircle(hc + Offset(hr * 0.2, hr * 0.6), hr * 0.3, _p(Colors.white));
      case 'goisagi':
        for (final dy in [0.0, 0.2]) {
          c.drawLine(hc + Offset(-hr * 0.5, -hr * 0.1 + hr * dy), hc + Offset(-hr * 2.6, hr * 0.7 + hr * dy), _stroke(Colors.white, 0.004));
        }
        c.drawCircle(hc + Offset(hr * 0.3, -hr * 0.15), hr * 0.3, _p(const Color(0xFFD83A2A)));
      case 'daisagi':
        c.drawLine(hc + Offset(hr * 0.2, hr * 0.15), hc + Offset(-hr * 0.4, hr * 0.15), _stroke(const Color(0xFFE8C83A), 0.005));
      case 'oshidori':
        c.drawPath(Path()..moveTo(-L * 0.1, bc.dy - L * 0.15)..lineTo(-L * 0.15, bc.dy - L * 0.55)..lineTo(L * 0.1, bc.dy - L * 0.2)..close(), _p(const Color(0xFFE8742A)));
        c.drawLine(hc + Offset(-hr * 0.4, -hr * 0.4), hc + Offset(-hr * 1.6, 0), _stroke(const Color(0xFFE8742A), 0.008));
        c.drawCircle(hc + Offset(-hr * 0.2, hr * 0.1), hr * 0.5, _p(Colors.white.withValues(alpha: 0.85)));
      case 'magamo':
        c.drawLine(hc + Offset(-hr * 0.2, hr * 0.95), hc + Offset(hr * 0.5, hr * 0.85), _stroke(Colors.white, 0.007));
      case 'tobi':
        c.drawLine(hc + Offset(-hr * 0.5, -hr * 0.1), hc + Offset(hr * 0.5, -hr * 0.1), _stroke(const Color(0xFF3A2A1E), 0.006));
      case 'umineko':
        c.drawLine(Offset(-L * 0.42 - s.tail * 0.7, bc.dy - L * 0.03), Offset(-L * 0.42 - s.tail * 0.7, bc.dy + L * 0.07), _stroke(Colors.black87, 0.01));
        c.drawCircle(hc + Offset(hr * 0.7 + L * s.beakLen * 0.85, hr * 0.15), hr * 0.12, _p(const Color(0xFFD83A2A)));
      case 'yamagara':
        c.drawCircle(hc + Offset(hr * 0.15, hr * 0.35), hr * 0.45, _p(const Color(0xFFF2E4B0)));
        c.drawCircle(hc + Offset(hr * 0.5, -hr * 0.45), hr * 0.3, _p(const Color(0xFFF2E4B0)));
      case 'misago':
        c.drawLine(hc + Offset(-hr * 0.8, -hr * 0.1), hc + Offset(hr * 0.5, -hr * 0.1), _stroke(const Color(0xFF3A2A1E), 0.009));
      case 'raicho':
        c.drawOval(Rect.fromCenter(center: hc + Offset(hr * 0.3, -hr * 0.6), width: hr * 0.75, height: hr * 0.3), _p(const Color(0xFFD83A2A)));
      case 'hoshigarasu':
        for (var k = 0; k < 14; k++) {
          c.drawCircle(Offset(-L * 0.4 + (k % 7) * L * 0.13, bc.dy - L * 0.18 + (k ~/ 7) * L * 0.2), L * 0.018, _p(Colors.white));
        }
      case 'iwahibari':
        c.drawOval(Rect.fromCenter(center: Offset(-L * 0.05, bc.dy + L * 0.08), width: L * 0.4, height: L * 0.16), _p(const Color(0xFFB86A3A)));
      case 'rurubitaki':
        c.drawOval(Rect.fromCenter(center: Offset(-L * 0.02, bc.dy + L * 0.06), width: L * 0.3, height: L * 0.16), _p(const Color(0xFFE8822A)));
        c.drawLine(hc + Offset(-hr * 0.2, -hr * 0.5), hc + Offset(hr * 0.7, -hr * 0.4), _stroke(Colors.white, 0.005));
      case 'suzume': // 茶色い頭・白い頬の黒点・黒いのど
        c.drawArc(Rect.fromCircle(center: hc, radius: hr), pi * 1.05, pi * 0.9, true, _p(const Color(0xFF8A4A2A)));
        c.drawCircle(hc + Offset(hr * 0.05, hr * 0.35), hr * 0.45, _p(Colors.white));
        c.drawCircle(hc + Offset(hr * 0.05, hr * 0.3), hr * 0.14, _p(Colors.black));
        c.drawOval(Rect.fromCenter(center: hc + Offset(hr * 0.5, hr * 0.8), width: hr * 0.6, height: hr * 0.4), _p(Colors.black));
      case 'shijukara': // 白い頬、黒いネクタイ模様
        c.drawCircle(hc + Offset(hr * 0.1, hr * 0.4), hr * 0.5, _p(Colors.white));
        c.drawLine(Offset(hc.dx + hr * 0.4, hc.dy + hr * 0.9), Offset(-L * 0.35, bc.dy + L * 0.05),
            _stroke(Colors.black, L * 0.09));
      case 'hiyodori': // 頬の茶色い斑、頭のとさか
        c.drawCircle(hc + Offset(-hr * 0.25, hr * 0.2), hr * 0.38, _p(const Color(0xFFA0603A)));
        c.drawPath(
            Path()
              ..moveTo(hc.dx - hr * 0.6, hc.dy - hr * 0.5)
              ..lineTo(hc.dx - hr * 1.2, hc.dy - hr * 0.9)
              ..lineTo(hc.dx - hr * 0.1, hc.dy - hr * 0.9)
              ..close(),
            _p(s.head));
      case 'kawasemi': // 青緑の背、オレンジの腹、長い嘴、頬のオレンジ
        c.drawLine(Offset(-L * 0.3, bc.dy - L * 0.18), Offset(L * 0.25, bc.dy - L * 0.2),
            _stroke(const Color(0xFF8AE0F0), L * 0.05));
        c.drawCircle(hc + Offset(-hr * 0.1, hr * 0.3), hr * 0.4, _p(const Color(0xFFE8822A)));
        c.drawCircle(hc + Offset(-hr * 0.5, hr * 0.7), hr * 0.25, _p(Colors.white));
      case 'kosagi': // 白い羽、冠羽、黄色い足
        for (final dy in [0.0, 0.25]) {
          c.drawLine(hc + Offset(-hr * 0.5, -hr * 0.1 + hr * dy), hc + Offset(-hr * 2.4, hr * 0.5 + hr * dy),
              _stroke(Colors.white, 0.005));
        }
        c.drawLine(Offset(L * 0.1, -0.005), Offset(L * 0.2, -0.005), _stroke(const Color(0xFFF2D24A), 0.008));
      case 'kaitsuburi': // 栗色の頬、嘴の付け根の黄白
        c.drawCircle(hc + Offset(-hr * 0.1, hr * 0.35), hr * 0.5, _p(const Color(0xFF9A4A2A)));
        c.drawCircle(hc + Offset(hr * 0.75, hr * 0.1), hr * 0.18, _p(const Color(0xFFF2EAB0)));
      case 'tsubame': // 赤いのど、青黒く光る背、長く二股の尾
        c.drawCircle(hc + Offset(hr * 0.25, hr * 0.55), hr * 0.5, _p(const Color(0xFFC0392B)));
        c.drawLine(Offset(-L * 0.3, bc.dy - L * 0.18), Offset(L * 0.2, bc.dy - L * 0.22),
            _stroke(const Color(0xFF5E86E0).withValues(alpha: 0.8), L * 0.05));
      case 'aosagi': // 灰色の羽、頭の黒い冠羽の線、黄色い嘴
        c.drawLine(hc + Offset(-hr * 0.2, -hr * 0.3), hc + Offset(-hr * 2.2, hr * 0.5), _stroke(Colors.black87, 0.008));
        c.drawLine(hc + Offset(hr * 0.1, hr * 0.5), Offset(L * 0.3, bc.dy - L * 0.05), _stroke(Colors.white70, 0.01));
      case 'onaga': // 黒い頭、空色の羽と尾（先は白）
        c.drawArc(Rect.fromCircle(center: hc, radius: hr), pi * 0.9, pi * 1.0, true, _p(Colors.black));
        c.drawCircle(Offset(-L * 0.42 - s.tail, bc.dy + L * 0.02), 0.008, _p(Colors.white));
      case 'kijibato': // 首の青灰と黒の縞模様、鱗模様の背
        for (var k = 0; k < 3; k++) {
          c.drawLine(hc + Offset(-hr * 0.2 + k * hr * 0.2, hr * 0.7),
              hc + Offset(-hr * 0.4 + k * hr * 0.2, hr * 1.25),
              _stroke(k.isEven ? Colors.black87 : const Color(0xFF8AA0C0), 0.008));
        }
        for (var k = 0; k < 6; k++) {
          c.drawArc(Rect.fromCenter(center: Offset(-L * 0.3 + k * L * 0.1, bc.dy - L * 0.08 + (k % 2) * 0.01), width: 0.016, height: 0.012),
              0, pi, false, _stroke(const Color(0xFF4A2A1A), 0.004));
        }
      case 'karugamo': // 淡い顔に黒い過眼線、黒い嘴の先が黄色
        c.drawLine(hc + Offset(-hr * 0.7, -hr * 0.2), hc + Offset(hr * 0.5, -hr * 0.15), _stroke(Colors.black87, 0.007));
        c.drawCircle(hc + Offset(hr * 0.7 + L * s.beakLen, hr * 0.07), hr * 0.12, _p(const Color(0xFFF2C21A)));
      case 'kawarabato': // 光沢のある首、翼の2本の黒帯、桃色の足
        for (var k = 0; k < 5; k++) {
          c.drawLine(hc + Offset(-hr * 0.5 + k * hr * 0.15, hr * 0.7), hc + Offset(-hr * 0.7 + k * hr * 0.15, hr * 1.2),
              _stroke(k.isEven ? const Color(0xFF3FA08A) : const Color(0xFF9A5ACF), 0.007));
        }
    }
  }

  // ---------------------------------------------------------------------
  // 魚（右向き・横から見た姿）
  // ---------------------------------------------------------------------

  static void _fin(Canvas c, Path fin, Color col, Offset rayFrom, List<Offset> rayTo) {
    c.drawPath(fin, _p(col.withValues(alpha: 0.78)));
    for (final o in rayTo) {
      c.drawLine(rayFrom, o, _stroke(_shade(col, 0.6).withValues(alpha: 0.6), 0.0018));
    }
    c.drawPath(fin, _stroke(_shade(col, 0.6).withValues(alpha: 0.5), 0.0022));
  }

  static void _fish(Canvas c, String id, double t, double ph) {
    final s = _fishSpecs[id] ?? _fishSpecs['koi']!;
    final L = s.len, H = s.h;
    final wag = sin(t * 5 + ph);
    c.save();
    c.translate(0, -0.035 + sin(t * 1.3 + ph) * 0.006);
    // 水面に映る影
    c.drawOval(Rect.fromCenter(center: const Offset(0, 0.04), width: L, height: L * 0.22),
        _p(Colors.black.withValues(alpha: 0.18)));

    if (id == 'unagi') {
      _eel(c, s, t, ph);
      c.restore();
      return;
    }

    final bodyRect = Rect.fromCenter(center: Offset.zero, width: L, height: H);
    final body = Path()
      ..moveTo(L * 0.5, H * 0.04)
      ..cubicTo(L * 0.42, -H * 0.5, L * 0.1, -H * 0.55, -L * 0.2, -H * 0.42)
      ..cubicTo(-L * 0.38, -H * 0.3, -L * 0.46, -H * 0.1, -L * 0.5, 0)
      ..cubicTo(-L * 0.46, H * 0.1, -L * 0.38, H * 0.3, -L * 0.2, H * 0.44)
      ..cubicTo(L * 0.1, H * 0.58, L * 0.42, H * 0.46, L * 0.5, H * 0.04)
      ..close();

    // 尾びれ（筋入り）
    final tailLen = L * s.tail;
    c.save();
    c.translate(-L * 0.48, 0);
    c.rotate(wag * 0.25);
    final tailPath = Path()
      ..moveTo(0, 0)
      ..lineTo(-tailLen, -H * s.tailSpread)
      ..quadraticBezierTo(-tailLen * 0.7, 0, -tailLen, H * s.tailSpread)
      ..close();
    _fin(c, tailPath, s.fin, Offset.zero,
        [for (var i = -3; i <= 3; i++) Offset(-tailLen * 0.97, H * s.tailSpread * i / 3.2)]);
    c.restore();

    // 背びれ・腹びれ（筋入り）
    final dorsal = Path()
      ..moveTo(-L * 0.18, -H * 0.4)
      ..quadraticBezierTo(-L * 0.02, -H * (0.45 + s.dorsal), L * 0.26, -H * 0.38)
      ..close();
    _fin(c, dorsal, s.fin, Offset(L * 0.04, -H * 0.4),
        [for (var i = 0; i < 5; i++) Offset(-L * 0.12 + i * L * 0.08, -H * (0.4 + s.dorsal * 0.8 * (1 - (i - 2).abs() / 3.5)))]);
    final ventral = Path()
      ..moveTo(-L * 0.05, H * 0.4)
      ..lineTo(-L * 0.2, H * 0.4 + H * 0.35)
      ..lineTo(L * 0.1, H * 0.38)
      ..close();
    _fin(c, ventral, s.fin, Offset(L * 0.0, H * 0.4),
        [for (var i = 0; i < 3; i++) Offset(-L * 0.18 + i * L * 0.07, H * 0.72)]);

    // 体（背→腹のグラデーション）
    c.drawPath(
        body,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_shade(s.back, 0.8), s.back, s.back, s.belly],
            stops: const [0, 0.25, 0.5, 1],
          ).createShader(bodyRect));

    // 模様・うろこ・光沢（体の形でクリップ）
    c.save();
    c.clipPath(body);
    _fishPattern(c, id, L, H);
    if (id != 'dojo' && id != 'medaka') {
      for (var row = -3; row <= 3; row++) {
        for (var k = -6; k <= 4; k++) {
          final x = k * L * 0.085 + (row.isOdd ? L * 0.042 : 0);
          c.drawArc(Rect.fromCenter(center: Offset(x, row * H * 0.15), width: L * 0.09, height: H * 0.2), -0.7, 1.9, false,
              _stroke(Colors.white.withValues(alpha: 0.13), 0.0016));
          c.drawArc(Rect.fromCenter(center: Offset(x, row * H * 0.15), width: L * 0.09, height: H * 0.2), 1.3, 1.2, false,
              _stroke(Colors.black.withValues(alpha: 0.1), 0.0016));
        }
      }
    }
    // 側線
    c.drawPath(
        Path()
          ..moveTo(L * 0.3, -H * 0.12)
          ..quadraticBezierTo(0, -H * 0.1, -L * 0.45, -H * 0.02),
        _stroke(Colors.black.withValues(alpha: 0.18), 0.0018));
    // 背の光沢
    c.drawRect(Rect.fromLTRB(-L * 0.5, -H * 0.55, L * 0.5, -H * 0.12),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: 0.38), Colors.transparent],
          ).createShader(Rect.fromLTRB(-L * 0.5, -H * 0.55, L * 0.5, -H * 0.12)));
    c.restore();
    c.drawPath(body, _stroke(Colors.black.withValues(alpha: 0.3), 0.0022));

    // えら蓋と胸びれ
    c.drawArc(Rect.fromCenter(center: Offset(L * 0.2, 0), width: L * 0.22, height: H * 0.9), -1.3, 2.6, false,
        _stroke(Colors.black.withValues(alpha: 0.28), 0.0025));
    c.drawPath(
        Path()
          ..moveTo(L * 0.12, H * 0.08)
          ..lineTo(-L * 0.04, H * 0.3 + sin(t * 4 + ph) * H * 0.04)
          ..lineTo(L * 0.02, H * 0.05)
          ..close(),
        _p(s.fin.withValues(alpha: 0.75)));

    // 目（リング・ハイライト）
    final eye = Offset(L * 0.34, -H * 0.1);
    c.drawCircle(eye, H * s.eye * 1.25, _p(Colors.black.withValues(alpha: 0.3)));
    c.drawCircle(eye, H * s.eye, _p(const Color(0xFFF2EBD0)));
    c.drawCircle(eye, H * s.eye * 0.62, _p(Colors.black));
    c.drawCircle(eye + Offset(H * s.eye * 0.2, -H * s.eye * 0.2), H * s.eye * 0.2, _p(Colors.white));

    // 口まわり
    if (id == 'koi') {
      for (final dy in [0.0, 0.1]) {
        c.drawLine(Offset(L * 0.48, H * (0.12 + dy)), Offset(L * 0.56, H * (0.3 + dy)), _stroke(Colors.white70, 0.003));
      }
    }
    c.restore();
  }

  static void _eel(Canvas c, _F s, double t, double ph) {
    final path = Path()..moveTo(s.len * 0.5, 0);
    const n = 24;
    for (var i = 1; i <= n; i++) {
      final f = i / n;
      path.lineTo(s.len * (0.5 - f), sin(f * 7 + t * 3 + ph) * 0.016 * f);
    }
    c.drawPath(path, _stroke(s.fin, 0.032));
    c.drawPath(path, _stroke(s.back, 0.024));
    c.save();
    c.translate(0, 0.007);
    c.drawPath(path, _stroke(s.belly.withValues(alpha: 0.75), 0.008));
    c.restore();
    c.save();
    c.translate(0, -0.008);
    c.drawPath(path, _stroke(Colors.white.withValues(alpha: 0.2), 0.004));
    c.restore();
    c.drawCircle(Offset(s.len * 0.47, -0.005), 0.0065, _p(const Color(0xFFE8E0C0)));
    c.drawCircle(Offset(s.len * 0.47, -0.005), 0.004, _p(Colors.black));
  }

  static void _fishPattern(Canvas c, String id, double L, double H) {
    switch (id) {
      case 'ayu':
        c.drawOval(Rect.fromCenter(center: Offset(L * 0.2, -H * 0.05), width: L * 0.08, height: H * 0.4), _p(const Color(0xFFF2C21A)));
      case 'oikawa':
        for (var i = 0; i < 6; i++) {
          c.drawRect(Rect.fromCenter(center: Offset(-L * 0.28 + i * L * 0.1, 0), width: L * 0.035, height: H * 0.9), _p(const Color(0xFF3FA08A).withValues(alpha: 0.55)));
        }
      case 'ugui':
        c.drawLine(Offset(-L * 0.4, H * 0.12), Offset(L * 0.4, H * 0.1), _stroke(const Color(0xFFE08A4A), 0.004));
      case 'tanago':
        c.drawLine(Offset(-L * 0.1, H * 0.05), Offset(-L * 0.5, H * 0.1), _stroke(const Color(0xFF2FA89A), 0.005));
        c.drawRect(Rect.fromCenter(center: Offset(L * 0.1, H * 0.2), width: L * 0.5, height: H * 0.18), _p(const Color(0xFFE88AA8).withValues(alpha: 0.5)));
      case 'namazu':
        final rng = Random(6);
        for (var i = 0; i < 14; i++) {
          c.drawCircle(Offset((rng.nextDouble() - 0.5) * L, (rng.nextDouble() - 0.5) * H * 0.7), H * 0.12, _p(const Color(0xFF6A6A58).withValues(alpha: 0.6)));
        }
        for (final dy in [-0.15, 0.15]) {
          c.drawLine(Offset(L * 0.5, H * dy), Offset(L * 0.78, H * (dy * 3)), _stroke(Colors.black87, 0.004));
        }
      case 'bora':
        for (var i = 0; i < 5; i++) {
          c.drawLine(Offset(-L * 0.4, -H * 0.05 + i * H * 0.1), Offset(L * 0.35, -H * 0.05 + i * H * 0.1), _stroke(const Color(0xFF6A7478).withValues(alpha: 0.5), 0.0025));
        }
      case 'kurodai':
        for (var i = 0; i < 5; i++) {
          c.drawRect(Rect.fromCenter(center: Offset(-L * 0.28 + i * L * 0.12, 0), width: L * 0.03, height: H * 0.9), _p(Colors.black.withValues(alpha: 0.22)));
        }
      case 'mebaru':
        final rng = Random(8);
        for (var i = 0; i < 12; i++) {
          c.drawOval(Rect.fromCenter(center: Offset((rng.nextDouble() - 0.5) * L, (rng.nextDouble() - 0.5) * H * 0.7), width: L * 0.1, height: H * 0.3), _p(const Color(0xFF8A3A2A).withValues(alpha: 0.5)));
        }
      case 'kasago':
        final rng = Random(10);
        for (var i = 0; i < 16; i++) {
          c.drawCircle(Offset((rng.nextDouble() - 0.5) * L, (rng.nextDouble() - 0.5) * H * 0.8), H * 0.12, _p(i.isEven ? const Color(0xFFF2E8D0) : const Color(0xFF4A2A1E)));
        }
      case 'suzuki':
        final rng = Random(12);
        for (var i = 0; i < 14; i++) {
          c.drawCircle(Offset(-L * 0.4 + rng.nextDouble() * L * 0.7, -H * 0.3 + rng.nextDouble() * H * 0.25), H * 0.05, _p(Colors.black.withValues(alpha: 0.55)));
        }
      case 'mahaze':
        final rng = Random(14);
        for (var i = 0; i < 6; i++) {
          c.drawOval(Rect.fromCenter(center: Offset(-L * 0.35 + i * L * 0.13, -H * 0.05), width: L * 0.08, height: H * 0.5), _p(const Color(0xFF4A3A22).withValues(alpha: 0.55)));
        }
      case 'nijimasu':
        c.drawRect(Rect.fromLTRB(-L * 0.45, -H * 0.05, L * 0.4, H * 0.12), _p(const Color(0xFFE88AA0).withValues(alpha: 0.6)));
        final rng = Random(16);
        for (var i = 0; i < 20; i++) {
          c.drawCircle(Offset(-L * 0.45 + rng.nextDouble() * L * 0.85, -H * 0.4 + rng.nextDouble() * H * 0.3), H * 0.04, _p(Colors.black.withValues(alpha: 0.55)));
        }
      case 'iwana':
        final rng = Random(18);
        for (var i = 0; i < 22; i++) {
          c.drawCircle(Offset(-L * 0.45 + rng.nextDouble() * L * 0.85, -H * 0.4 + rng.nextDouble() * H * 0.6), H * 0.06, _p(const Color(0xFFEFE6C0)));
        }
      case 'koi': // 紅白の模様
        c.drawOval(Rect.fromCenter(center: Offset(-L * 0.15, -H * 0.15), width: L * 0.34, height: H * 0.7), _p(const Color(0xFFE8602A)));
        c.drawOval(Rect.fromCenter(center: Offset(L * 0.2, -H * 0.2), width: L * 0.22, height: H * 0.5), _p(const Color(0xFFD83A2A)));
        c.drawOval(Rect.fromCenter(center: Offset(-L * 0.32, H * 0.1), width: L * 0.2, height: H * 0.4), _p(Colors.black87));
      case 'funa':
        c.drawRect(Rect.fromLTRB(-L * 0.5, -H * 0.5, L * 0.5, -H * 0.1), _p(const Color(0xFF6A6A4A).withValues(alpha: 0.35)));
      case 'medaka': // 透きとおった体と大きな目、背の黄みがかった色
        c.drawRect(Rect.fromCenter(center: Offset(-L * 0.1, -H * 0.3), width: L * 0.6, height: H * 0.2), _p(const Color(0xFFE8D28A)));
        c.drawLine(Offset(-L * 0.3, -H * 0.05), Offset(L * 0.25, -H * 0.05), _stroke(const Color(0xFFB8B090), 0.002));
      case 'yamame': // パーマーク（楕円の斑紋）と赤い点
        for (var i = 0; i < 7; i++) {
          c.drawOval(Rect.fromCenter(center: Offset(-L * 0.32 + i * L * 0.11, -H * 0.02), width: L * 0.06, height: H * 0.55),
              _p(const Color(0xFF4A5A4A).withValues(alpha: 0.7)));
        }
        for (var i = 0; i < 5; i++) {
          c.drawCircle(Offset(-L * 0.25 + i * L * 0.12, H * 0.15), H * 0.06, _p(const Color(0xFFD8503A)));
        }
      case 'dojo': // 褐色のまだら模様
        final rng = Random(2);
        for (var i = 0; i < 16; i++) {
          c.drawCircle(Offset((rng.nextDouble() - 0.5) * L, (rng.nextDouble() - 0.5) * H * 0.7), H * 0.13, _p(const Color(0xFF5A4630).withValues(alpha: 0.8)));
        }
        for (final dy in [-0.1, 0.0, 0.1]) {
          c.drawLine(Offset(L * 0.5, H * dy), Offset(L * 0.6, H * (dy + 0.5)), _stroke(Colors.black54, 0.003));
        }
      case 'donko': // 暗褐色の斑と大きな頭
        final rng = Random(9);
        for (var i = 0; i < 12; i++) {
          c.drawOval(Rect.fromCenter(center: Offset((rng.nextDouble() - 0.5) * L, (rng.nextDouble() - 0.5) * H * 0.7), width: L * 0.12, height: H * 0.3),
              _p(const Color(0xFF2E2418).withValues(alpha: 0.75)));
        }
        c.drawOval(Rect.fromCenter(center: Offset(L * 0.28, H * 0.06), width: L * 0.42, height: H * 1.0), _p(const Color(0xFF4A3A28).withValues(alpha: 0.6)));
      case 'bluegill': // 縦縞、黒い耳ぶた、橙の腹
        for (var i = 0; i < 5; i++) {
          c.drawRect(Rect.fromCenter(center: Offset(-L * 0.25 + i * L * 0.13, -H * 0.1), width: L * 0.04, height: H * 0.8),
              _p(Colors.black.withValues(alpha: 0.25)));
        }
        c.drawCircle(Offset(L * 0.24, H * 0.0), H * 0.12, _p(const Color(0xFF16162A)));
        c.drawRect(Rect.fromCenter(center: Offset(0, H * 0.38), width: L, height: H * 0.24), _p(const Color(0xFFE88A2A)));
      case 'magochi': // 砂色に黒い斑点、平たい頭
        final rng = Random(4);
        for (var i = 0; i < 20; i++) {
          c.drawCircle(Offset((rng.nextDouble() - 0.5) * L, (rng.nextDouble() - 0.5) * H * 0.8), H * 0.08, _p(const Color(0xFF5A4A30)));
        }
      case 'kumanomi': // 3本の白い帯（黒縁つき）
        for (final f in [0.3, -0.05, -0.38]) {
          final w = f == 0.3 ? 0.07 : 0.09;
          c.drawRect(Rect.fromCenter(center: Offset(L * f, 0), width: L * (w + 0.03), height: H * 1.2), _p(Colors.black));
          c.drawRect(Rect.fromCenter(center: Offset(L * f, 0), width: L * w, height: H * 1.2), _p(Colors.white));
        }
      case 'chochouchakuo': // 黄色い体の横縞、目を通る黒帯とその後ろの白帯
        for (var i = -3; i <= 3; i++) {
          c.drawLine(Offset(-L * 0.5, i * H * 0.13), Offset(L * 0.3, i * H * 0.13), _stroke(const Color(0xFF9A7A1A).withValues(alpha: 0.5), 0.0022));
        }
        c.drawRect(Rect.fromCenter(center: Offset(L * 0.17, 0), width: L * 0.07, height: H * 1.2), _p(Colors.white));
        c.drawRect(Rect.fromCenter(center: Offset(L * 0.31, 0), width: L * 0.07, height: H * 1.2), _p(Colors.black87));
      case 'mejina': // 濃い灰青色、うろこの白い縁取り
        c.drawRect(Rect.fromLTRB(-L * 0.5, H * 0.1, L * 0.5, H * 0.5), _p(const Color(0xFF8A94A0).withValues(alpha: 0.3)));
    }
  }
}

// -----------------------------------------------------------------------
// 種ごとの寸法・色
// -----------------------------------------------------------------------

class _B {
  final double len, beakLen, tail, neck, leg, headR, wingLen;
  final Color back, belly, head, wing, beak, tailColor, neckColor, legColor;
  final bool fork, floating, wingBars;
  const _B({
    required this.len,
    required this.back,
    required this.belly,
    required this.head,
    required this.wing,
    required this.beak,
    this.beakLen = 0.3,
    this.tail = 0.05,
    this.neck = 0,
    this.leg = 0.02,
    this.headR = 0.2,
    this.wingLen = 0.6,
    this.tailColor = const Color(0xFF3A3028),
    this.neckColor = const Color(0xFFCCCCCC),
    this.legColor = const Color(0xFF6A4A3A),
    this.fork = false,
    this.floating = false,
    this.wingBars = false,
  });
}

const _birdSpecs = <String, _B>{
  'suzume': _B(len: 0.1, back: Color(0xFF9A6A3E), belly: Color(0xFFD8C8A8), head: Color(0xFFB88A5A),
      wing: Color(0xFF6A4A2A), beak: Color(0xFF3A3028), tail: 0.05, tailColor: Color(0xFF6A4A2A), beakLen: 0.22),
  'shijukara': _B(len: 0.1, back: Color(0xFF7A8A8A), belly: Color(0xFFEDE8D8), head: Color(0xFF1A1A1A),
      wing: Color(0xFF5A6A6A), beak: Color(0xFF222222), tail: 0.05, tailColor: Color(0xFF5A6A6A), beakLen: 0.18),
  'hiyodori': _B(len: 0.13, back: Color(0xFF7A7A80), belly: Color(0xFFA0A0A6), head: Color(0xFF8A8A92),
      wing: Color(0xFF5A5A62), beak: Color(0xFF3A3A3A), tail: 0.09, tailColor: Color(0xFF5A5A62), headR: 0.19),
  'kawasemi': _B(len: 0.11, back: Color(0xFF1E9EC8), belly: Color(0xFFE8822A), head: Color(0xFF1E8AB0),
      wing: Color(0xFF1A7AA8), beak: Color(0xFF222222), beakLen: 0.75, tail: 0.03, tailColor: Color(0xFF1A7AA8), leg: 0.015,
      legColor: Color(0xFFD8503A)),
  'kosagi': _B(len: 0.15, back: Colors.white, belly: Color(0xFFF4F4F0), head: Colors.white,
      wing: Color(0xFFE8E8E4), beak: Color(0xFF1A1A1A), beakLen: 0.7, neck: 0.07, leg: 0.1, tail: 0.06,
      tailColor: Colors.white, neckColor: Colors.white, legColor: Color(0xFF2A2A2A), headR: 0.13),
  'kaitsuburi': _B(len: 0.1, back: Color(0xFF6E5236), belly: Color(0xFF8A6A48), head: Color(0xFF5A4630),
      wing: Color(0xFF5A4630), beak: Color(0xFF3A3028), beakLen: 0.18, tail: 0.01, floating: true, leg: 0.0,
      tailColor: Color(0xFF6E5236)),
  'tsubame': _B(len: 0.11, back: Color(0xFF1F3E8A), belly: Color(0xFFF2E8D8), head: Color(0xFF1F3E8A),
      wing: Color(0xFF16306E), beak: Color(0xFF1A1A1A), beakLen: 0.14, tail: 0.13, fork: true, wingLen: 0.85,
      tailColor: Color(0xFF16306E), leg: 0.015, headR: 0.18),
  'aosagi': _B(len: 0.2, back: Color(0xFF7A8AA0), belly: Color(0xFFD8DCE4), head: Colors.white,
      wing: Color(0xFF5E6E88), beak: Color(0xFFE8B83A), beakLen: 0.8, neck: 0.11, leg: 0.15, tail: 0.07,
      tailColor: Color(0xFF5E6E88), neckColor: Color(0xFFE8ECF0), legColor: Color(0xFF8A7A4A), headR: 0.1),
  'onaga': _B(len: 0.13, back: Color(0xFFB8A89A), belly: Color(0xFFE8E0D4), head: Color(0xFF1A1A1A),
      wing: Color(0xFF5E9AD8), beak: Color(0xFF2A2A2A), beakLen: 0.2, tail: 0.16, tailColor: Color(0xFF5E9AD8), headR: 0.18),
  'kijibato': _B(len: 0.14, back: Color(0xFF7A5A44), belly: Color(0xFFB8A090), head: Color(0xFF9AA0A8),
      wing: Color(0xFF8A6244), beak: Color(0xFF3A3A3A), beakLen: 0.18, tail: 0.07, tailColor: Color(0xFF4A3A30), headR: 0.17,
      legColor: Color(0xFFC0506A)),
  'karugamo': _B(len: 0.15, back: Color(0xFF7A6040), belly: Color(0xFF9A8060), head: Color(0xFFD8C8A0),
      wing: Color(0xFF5A4630), beak: Color(0xFF1A1A1A), beakLen: 0.45, tail: 0.03, floating: true, leg: 0.0,
      tailColor: Color(0xFF5A4630), headR: 0.17),
  'kawarabato': _B(len: 0.14, back: Color(0xFF9AA0A8), belly: Color(0xFFB4BAC0), head: Color(0xFF7A8088),
      wing: Color(0xFFA8B0B8), beak: Color(0xFF3A3A3A), beakLen: 0.18, tail: 0.07, tailColor: Color(0xFF5A6068), headR: 0.17,
      legColor: Color(0xFFD8708A), wingBars: true),
  'uguisu': _B(len: 0.1, back: Color(0xFF8A8458), belly: Color(0xFFE0DCC4), head: Color(0xFF8A8458), wing: Color(0xFF6E6A44), beak: Color(0xFF4A3A30), beakLen: 0.2, tail: 0.07, tailColor: Color(0xFF6E6A44)),
  'mejiro': _B(len: 0.09, back: Color(0xFF8AA648), belly: Color(0xFFE8E4D0), head: Color(0xFF8AA648), wing: Color(0xFF6A8A38), beak: Color(0xFF4A4A44), beakLen: 0.2, tail: 0.04, tailColor: Color(0xFF6A8A38)),
  'joubitaki': _B(len: 0.11, back: Color(0xFF6A6A6E), belly: Color(0xFFE88A3A), head: Color(0xFFC8C8CC), wing: Color(0xFF3A3A3E), beak: Color(0xFF1A1A1A), beakLen: 0.18, tail: 0.07, tailColor: Color(0xFFD87A3A)),
  'kisekirei': _B(len: 0.11, back: Color(0xFF7E8A94), belly: Color(0xFFF2D83A), head: Color(0xFF7E8A94), wing: Color(0xFF4E5A64), beak: Color(0xFF2A2A2A), beakLen: 0.24, tail: 0.18, leg: 0.03, tailColor: Color(0xFF3A3A3E), legColor: Color(0xFFD8A8A0)),
  'hakusekirei': _B(len: 0.11, back: Color(0xFF6A6E74), belly: Color(0xFFF4F4F2), head: Color(0xFFF4F4F2), wing: Color(0xFF4A4E54), beak: Color(0xFF1A1A1A), beakLen: 0.24, tail: 0.17, leg: 0.03, tailColor: Color(0xFF2A2A2E), legColor: Color(0xFF2A2A2A)),
  'kawau': _B(len: 0.2, back: Color(0xFF1E2A32), belly: Color(0xFF2A3640), head: Color(0xFF1E2A32), wing: Color(0xFF2E4A54), beak: Color(0xFF8A8A84), beakLen: 0.45, tail: 0.09, leg: 0.03, neck: 0.04, tailColor: Color(0xFF1E2A32), neckColor: Color(0xFF1E2A32), legColor: Color(0xFF2A2A2A), headR: 0.12, wingLen: 0.7),
  'goisagi': _B(len: 0.15, back: Color(0xFF2E4A44), belly: Color(0xFFE8E8E0), head: Color(0xFF1E3A34), wing: Color(0xFF8A9AA0), beak: Color(0xFF1A1A1A), beakLen: 0.5, neck: 0.03, leg: 0.07, tail: 0.04, tailColor: Color(0xFF8A9AA0), neckColor: Color(0xFFE0E0D8), legColor: Color(0xFFC8B84A), headR: 0.15),
  'daisagi': _B(len: 0.22, back: Colors.white, belly: Color(0xFFF8F8F4), head: Colors.white, wing: Color(0xFFEDEDE8), beak: Color(0xFFE8C83A), beakLen: 0.7, neck: 0.14, leg: 0.16, tail: 0.07, tailColor: Colors.white, neckColor: Colors.white, legColor: Color(0xFF2A2A2A), headR: 0.09),
  'oshidori': _B(len: 0.13, back: Color(0xFF6A4A3A), belly: Color(0xFFF4EAD8), head: Color(0xFF3A6A58), wing: Color(0xFFD8742A), beak: Color(0xFFD84A3A), beakLen: 0.25, tail: 0.04, floating: true, leg: 0.0, tailColor: Color(0xFF3A3A44), headR: 0.17),
  'magamo': _B(len: 0.15, back: Color(0xFF8A8478), belly: Color(0xFFC8C4B8), head: Color(0xFF1E6A3A), wing: Color(0xFF6E6A5E), beak: Color(0xFFE8C82A), beakLen: 0.4, tail: 0.03, floating: true, leg: 0.0, tailColor: Color(0xFF2A2A30), headR: 0.17),
  'tobi': _B(len: 0.2, back: Color(0xFF6A4A32), belly: Color(0xFF8A6A4A), head: Color(0xFFC8B89A), wing: Color(0xFF5A3E2A), beak: Color(0xFF4A4A44), beakLen: 0.3, tail: 0.1, leg: 0.03, tailColor: Color(0xFF5A3E2A), headR: 0.16, wingLen: 0.95, fork: true, legColor: Color(0xFFD8B84A)),
  'umineko': _B(len: 0.16, back: Color(0xFF6E7684), belly: Colors.white, head: Colors.white, wing: Color(0xFF5E6674), beak: Color(0xFFE8C83A), beakLen: 0.4, tail: 0.06, leg: 0.04, tailColor: Colors.white, headR: 0.16, wingLen: 0.8, legColor: Color(0xFFE8C83A)),
  'yamagara': _B(len: 0.1, back: Color(0xFF7A8088), belly: Color(0xFFC8683A), head: Color(0xFF1A1A1A), wing: Color(0xFF5A6068), beak: Color(0xFF222222), beakLen: 0.18, tail: 0.05, tailColor: Color(0xFF5A6068)),
  'misago': _B(len: 0.19, back: Color(0xFF4E3A2A), belly: Color(0xFFF4F0E8), head: Color(0xFFF4F0E8), wing: Color(0xFF4A382A), beak: Color(0xFF1A1A1A), beakLen: 0.28, tail: 0.1, leg: 0.03, tailColor: Color(0xFF4A382A), headR: 0.15, wingLen: 0.95, legColor: Color(0xFF8AA0B0)),
  'raicho': _B(len: 0.14, back: Color(0xFF8A6A48), belly: Color(0xFFD8D0C0), head: Color(0xFF7A5A3A), wing: Color(0xFFE8E4DA), beak: Color(0xFF1A1A1A), beakLen: 0.15, tail: 0.05, leg: 0.02, tailColor: Color(0xFF3A3028), legColor: Color(0xFFE8E4DA), headR: 0.17),
  'hoshigarasu': _B(len: 0.17, back: Color(0xFF4A3A2E), belly: Color(0xFF5A4636), head: Color(0xFF4A3A2E), wing: Color(0xFF2E2620), beak: Color(0xFF1A1A1A), beakLen: 0.55, tail: 0.06, leg: 0.03, tailColor: Color(0xFF2E2620), legColor: Color(0xFF2A2A2A), headR: 0.17),
  'iwahibari': _B(len: 0.11, back: Color(0xFF7A6A58), belly: Color(0xFFB8B0A4), head: Color(0xFF8A8C90), wing: Color(0xFF5A4A3A), beak: Color(0xFF3A3A3A), beakLen: 0.22, tail: 0.06, tailColor: Color(0xFF5A4A3A)),
  'rurubitaki': _B(len: 0.11, back: Color(0xFF3A6AC8), belly: Color(0xFFF0ECE0), head: Color(0xFF3A6AC8), wing: Color(0xFF2E5AB0), beak: Color(0xFF1A1A1A), beakLen: 0.18, tail: 0.06, tailColor: Color(0xFF2E5AB0)),
  'enaga': _B(len: 0.08, back: Color(0xFF3A3A3E), belly: Color(0xFFF4F0EC), head: Color(0xFFF8F4F0), wing: Color(0xFF4A4A50), beak: Color(0xFF222222), beakLen: 0.1, tail: 0.16, tailColor: Color(0xFF2A2A2E)),
  'ooruri': _B(len: 0.12, back: Color(0xFF2A4AC8), belly: Color(0xFFF4F4F0), head: Color(0xFF2A4AC8), wing: Color(0xFF1E3AA0), beak: Color(0xFF1A1A1A), beakLen: 0.18, tail: 0.06),
  'kibitaki': _B(len: 0.11, back: Color(0xFF2A2A2E), belly: Color(0xFFF2C21A), head: Color(0xFF2A2A2E), wing: Color(0xFF1E1E22), beak: Color(0xFF1A1A1A), beakLen: 0.15, tail: 0.05),
  'shimaenaga': _B(len: 0.08, back: Color(0xFFF8F8F6), belly: Color(0xFFFBFBFA), head: Color(0xFFFBFBFA), wing: Color(0xFF4A4A50), beak: Color(0xFF222222), beakLen: 0.1, tail: 0.16),
  'hoojiro': _B(len: 0.12, back: Color(0xFF8A5A3A), belly: Color(0xFFC8885A), head: Color(0xFFE8E0D4), wing: Color(0xFF6A4A32), beak: Color(0xFF3A3A3A), beakLen: 0.14, tail: 0.1),
  'shime': _B(len: 0.12, back: Color(0xFF7A5A3A), belly: Color(0xFFC8A07A), head: Color(0xFFA87A52), wing: Color(0xFF3A3A3E), beak: Color(0xFFC8B060), beakLen: 0.2, tail: 0.05),
  'kawarahiwa': _B(len: 0.12, back: Color(0xFF8A8A4A), belly: Color(0xFFC8C070), head: Color(0xFF8A8A4A), wing: Color(0xFF5A5A32), beak: Color(0xFFD8C8A0), beakLen: 0.18, tail: 0.06),
  'tsugumi': _B(len: 0.2, back: Color(0xFF6A4A32), belly: Color(0xFFEDE0D0), head: Color(0xFF5A3E2A), wing: Color(0xFF8A4A2A), beak: Color(0xFFC8A040), beakLen: 0.18, tail: 0.08),
  'shirohara': _B(len: 0.2, back: Color(0xFF7A6A52), belly: Color(0xFFF0E8DC), head: Color(0xFF6A5A44), wing: Color(0xFF5A4A36), beak: Color(0xFFC8A040), beakLen: 0.16, tail: 0.08),
  'akahara': _B(len: 0.2, back: Color(0xFF6A5A3A), belly: Color(0xFFD8885A), head: Color(0xFF6A5A3A), wing: Color(0xFF4A3E2A), beak: Color(0xFFC8A040), beakLen: 0.16, tail: 0.08),
  'kakesu': _B(len: 0.26, back: Color(0xFFB8887A), belly: Color(0xFFC8A090), head: Color(0xFFB8887A), wing: Color(0xFF2A3AA0), beak: Color(0xFF2A2A2A), beakLen: 0.18, tail: 0.1),
  'ooakagera': _B(len: 0.28, back: Color(0xFF2A2A2E), belly: Color(0xFFF0E8E0), head: Color(0xFFF0E8E0), wing: Color(0xFF3A3A3E), beak: Color(0xFF2A2A2A), beakLen: 0.3, tail: 0.1, tailColor: Color(0xFF2A2A2E)),
  'akagera': _B(len: 0.24, back: Color(0xFF2A2A2E), belly: Color(0xFFF0E8E0), head: Color(0xFF2A2A2E), wing: Color(0xFF3A3A3E), beak: Color(0xFF2A2A2A), beakLen: 0.28, tail: 0.1),
  'kogera': _B(len: 0.1, back: Color(0xFF6A5A4A), belly: Color(0xFFE8E0D0), head: Color(0xFF5A4A3A), wing: Color(0xFF4A3E32), beak: Color(0xFF2A2A2A), beakLen: 0.16, tail: 0.08),
  'fukurou': _B(len: 0.3, back: Color(0xFFA89A8A), belly: Color(0xFFE8E0D4), head: Color(0xFFC8BCAA), wing: Color(0xFF7A6E5E), beak: Color(0xFF8A7A5A), beakLen: 0.08, tail: 0.1, headR: 0.26),
  'ooshima_fukurou': _B(len: 0.4, back: Color(0xFF8A7A62), belly: Color(0xFFC8B8A0), head: Color(0xFF9A8A72), wing: Color(0xFF6A5A44), beak: Color(0xFF3A3A3A), beakLen: 0.1, tail: 0.12, headR: 0.26),
  'ootaka': _B(len: 0.28, back: Color(0xFF5A5E66), belly: Color(0xFFE8E4DC), head: Color(0xFF3A3E46), wing: Color(0xFF4A4E56), beak: Color(0xFF3A3A3A), beakLen: 0.2, tail: 0.14, wingLen: 0.8),
  'inuwashi': _B(len: 0.4, back: Color(0xFF4A3A2A), belly: Color(0xFF6A5240), head: Color(0xFFC8A060), wing: Color(0xFF3E2E22), beak: Color(0xFF3A3A3A), beakLen: 0.25, tail: 0.16, wingLen: 1.0),
  'hayabusa': _B(len: 0.3, back: Color(0xFF4A5A6A), belly: Color(0xFFF0E8DC), head: Color(0xFF2A3038), wing: Color(0xFF3A4650), beak: Color(0xFF2A2A2A), beakLen: 0.15, tail: 0.12, wingLen: 0.9),
  'kumataka': _B(len: 0.36, back: Color(0xFF5A4A3A), belly: Color(0xFFE8DCC8), head: Color(0xFF5A4A3A), wing: Color(0xFF4A3A2E), beak: Color(0xFF3A3A3A), beakLen: 0.2, tail: 0.15, wingLen: 0.95),
  'yamadori': _B(len: 0.34, back: Color(0xFFA85A2A), belly: Color(0xFFC8783A), head: Color(0xFFA85A2A), wing: Color(0xFF8A4A22), beak: Color(0xFFC8C0B0), beakLen: 0.14, tail: 0.45, leg: 0.06, legColor: Color(0xFF8A7A6A)),
  'kiji': _B(len: 0.3, back: Color(0xFF3A7A5A), belly: Color(0xFF4A6A4A), head: Color(0xFF1E4A6A), wing: Color(0xFF8A6A3A), beak: Color(0xFFC8C0A0), beakLen: 0.14, tail: 0.36, leg: 0.06, legColor: Color(0xFF8A7A6A)),
  'hototogisu': _B(len: 0.2, back: Color(0xFF7A8088), belly: Color(0xFFEDEBE4), head: Color(0xFF6A7078), wing: Color(0xFF5A6068), beak: Color(0xFF3A3A3A), beakLen: 0.2, tail: 0.14),
  'kakkou': _B(len: 0.28, back: Color(0xFF7A8088), belly: Color(0xFFEDEBE4), head: Color(0xFF6A7078), wing: Color(0xFF5A6068), beak: Color(0xFF3A3A3A), beakLen: 0.2, tail: 0.14),
  'ooyoshikiri': _B(len: 0.18, back: Color(0xFF8A7A52), belly: Color(0xFFE0D8C0), head: Color(0xFF8A7A52), wing: Color(0xFF6A5A3A), beak: Color(0xFF3A3A3A), beakLen: 0.22, tail: 0.08),
  'kogamo': _B(len: 0.18, back: Color(0xFF8A8478), belly: Color(0xFFEDE8D8), head: Color(0xFF8A3A2A), wing: Color(0xFF6A6458), beak: Color(0xFF2A2A2A), beakLen: 0.18, tail: 0.05, floating: true, leg: 0.0, headR: 0.17),
  'hidorigamo': _B(len: 0.2, back: Color(0xFF8A8A8A), belly: Color(0xFFF0ECE4), head: Color(0xFF8A4A2A), wing: Color(0xFF6A6A6A), beak: Color(0xFF8AA0B0), beakLen: 0.14, tail: 0.05, floating: true, leg: 0.0, headR: 0.17),
  'kinkurohajiro': _B(len: 0.17, back: Color(0xFF1E1E22), belly: Color(0xFFF4F4F0), head: Color(0xFF1E1E22), wing: Color(0xFF2E2E32), beak: Color(0xFF6A7A8A), beakLen: 0.18, tail: 0.04, floating: true, leg: 0.0, headR: 0.17),
  'oomizunagidori': _B(len: 0.28, back: Color(0xFF6A5A4A), belly: Color(0xFFF4F0E8), head: Color(0xFFB8A890), wing: Color(0xFF4A3E32), beak: Color(0xFF8A8A94), beakLen: 0.3, tail: 0.07, wingLen: 1.0, leg: 0.03),
  'kamome': _B(len: 0.22, back: Color(0xFFC8C8CC), belly: Color(0xFFFBFBFA), head: Color(0xFFFBFBFA), wing: Color(0xFFB0B0B6), beak: Color(0xFFD8503A), beakLen: 0.28, tail: 0.07, leg: 0.04, legColor: Color(0xFFD8503A), wingLen: 0.8),
  'ooseguro': _B(len: 0.3, back: Color(0xFF4A4E54), belly: Color(0xFFFBFBFA), head: Color(0xFFFBFBFA), wing: Color(0xFF3A3E44), beak: Color(0xFFE8C83A), beakLen: 0.3, tail: 0.08, leg: 0.04, legColor: Color(0xFFE8A0A0), wingLen: 0.9),
  'ibisu': _B(len: 0.3, back: Color(0xFFF4E8E4), belly: Color(0xFFF8F0EC), head: Color(0xFFF8F0EC), wing: Color(0xFFF0D8D0), beak: Color(0xFF2A2A2A), beakLen: 0.55, tail: 0.06, neck: 0.08, leg: 0.1, legColor: Color(0xFFD8503A), headR: 0.12),
  'kounotori': _B(len: 0.38, back: Color(0xFFF8F8F6), belly: Color(0xFFFBFBFA), head: Color(0xFFFBFBFA), wing: Color(0xFF2A2A2E), beak: Color(0xFF2A2A2A), beakLen: 0.7, tail: 0.07, neck: 0.12, leg: 0.16, legColor: Color(0xFFD8503A), headR: 0.1),
  'tancho': _B(len: 0.42, back: Color(0xFFF8F8F6), belly: Color(0xFFFBFBFA), head: Color(0xFFF8F8F6), wing: Color(0xFF2A2A2E), beak: Color(0xFFC8B890), beakLen: 0.5, tail: 0.06, neck: 0.14, leg: 0.18, legColor: Color(0xFF2A2A2A), headR: 0.1),
  'shigi': _B(len: 0.2, back: Color(0xFF6A5A3A), belly: Color(0xFFE8D8B8), head: Color(0xFF8A7A52), wing: Color(0xFF4A3E2A), beak: Color(0xFF8A7A62), beakLen: 0.7, tail: 0.04, leg: 0.06),
  'ban': _B(len: 0.2, back: Color(0xFF3A3A44), belly: Color(0xFF5A5A64), head: Color(0xFF2A2A32), wing: Color(0xFF3A3A3E), beak: Color(0xFFD8503A), beakLen: 0.12, tail: 0.06, leg: 0.05, legColor: Color(0xFFC8C84A)),
  'yamasemi': _B(len: 0.28, back: Color(0xFF3A3A3E), belly: Color(0xFFF4F4F0), head: Color(0xFFF4F4F0), wing: Color(0xFF2A2A2E), beak: Color(0xFF2A2A2A), beakLen: 0.45, tail: 0.08, headR: 0.24),
  'akashoubin': _B(len: 0.26, back: Color(0xFFD8503A), belly: Color(0xFFE8803A), head: Color(0xFFD8503A), wing: Color(0xFFC8402A), beak: Color(0xFFE83A2A), beakLen: 0.4, tail: 0.07),
  'karasu': _B(len: 0.3, back: Color(0xFF1E1E24), belly: Color(0xFF2A2A32), head: Color(0xFF1E1E24), wing: Color(0xFF2E2E3A), beak: Color(0xFF1A1A1A), beakLen: 0.36, tail: 0.1),
};

class _F {
  final double len, h, tail, dorsal, eye;
  final Color back, belly, fin;
  double get tailSpread => 0.5;
  const _F({
    required this.len,
    required this.h,
    required this.back,
    required this.belly,
    required this.fin,
    this.tail = 0.22,
    this.dorsal = 0.5,
    this.eye = 0.11,
  });
}

const _fishSpecs = <String, _F>{
  'koi': _F(len: 0.16, h: 0.055, back: Color(0xFFF2EEE6), belly: Color(0xFFF8F6F0), fin: Color(0xFFE8A07A)),
  'funa': _F(len: 0.13, h: 0.06, back: Color(0xFF8A8A6A), belly: Color(0xFFD8D4B0), fin: Color(0xFF9A9A7A), dorsal: 0.6),
  'medaka': _F(len: 0.075, h: 0.018, back: Color(0xFFD8D0A8), belly: Color(0xFFEAE6D0), fin: Color(0xFFE8E2C8), eye: 0.2, tail: 0.2),
  'yamame': _F(len: 0.14, h: 0.034, back: Color(0xFF7A8A5E), belly: Color(0xFFE8DCC8), fin: Color(0xFF9A8A6A), dorsal: 0.4),
  'dojo': _F(len: 0.14, h: 0.02, back: Color(0xFFB89A5A), belly: Color(0xFFE0CC9A), fin: Color(0xFFB8A068), tail: 0.12, dorsal: 0.3),
  'donko': _F(len: 0.11, h: 0.04, back: Color(0xFF6A5A40), belly: Color(0xFF9A8A68), fin: Color(0xFF6A5A40), tail: 0.18, dorsal: 0.45, eye: 0.09),
  'unagi': _F(len: 0.24, h: 0.02, back: Color(0xFF3A3A33), belly: Color(0xFFC8C4A8), fin: Color(0xFF2A2A26)),
  'bluegill': _F(len: 0.1, h: 0.07, back: Color(0xFF6A7A4A), belly: Color(0xFFD8B070), fin: Color(0xFF7A8A5A), dorsal: 0.7, tail: 0.2),
  'magochi': _F(len: 0.15, h: 0.026, back: Color(0xFFB8A078), belly: Color(0xFFE8DCC0), fin: Color(0xFFA89068), tail: 0.14, dorsal: 0.35, eye: 0.14),
  'kumanomi': _F(len: 0.095, h: 0.055, back: Color(0xFFF08A2A), belly: Color(0xFFF2A04A), fin: Color(0xFFF08A2A), tail: 0.2, dorsal: 0.4),
  'chochouchakuo': _F(len: 0.09, h: 0.075, back: Color(0xFFF2D24A), belly: Color(0xFFF6E08A), fin: Color(0xFFF2D24A), tail: 0.16, dorsal: 0.9),
  'mejina': _F(len: 0.13, h: 0.06, back: Color(0xFF3E4650), belly: Color(0xFF6A7480), fin: Color(0xFF2E343C), dorsal: 0.5),
  'ayu': _F(len: 0.13, h: 0.032, back: Color(0xFF8A9A5A), belly: Color(0xFFEAE4C8), fin: Color(0xFFB8B070), dorsal: 0.4),
  'oikawa': _F(len: 0.12, h: 0.036, back: Color(0xFF7A8A8A), belly: Color(0xFFE8E4D8), fin: Color(0xFFE08A4A), dorsal: 0.5),
  'ugui': _F(len: 0.15, h: 0.038, back: Color(0xFF6A7A5A), belly: Color(0xFFEAE4D0), fin: Color(0xFFA89A7A), dorsal: 0.4),
  'tanago': _F(len: 0.09, h: 0.04, back: Color(0xFF6A8AA8), belly: Color(0xFFE8D8D0), fin: Color(0xFFE08A8A), dorsal: 0.45, eye: 0.12),
  'namazu': _F(len: 0.17, h: 0.045, back: Color(0xFF3A3A32), belly: Color(0xFF8A8A78), fin: Color(0xFF3A3A32), tail: 0.14, dorsal: 0.1, eye: 0.07),
  'bora': _F(len: 0.15, h: 0.04, back: Color(0xFF7A8A92), belly: Color(0xFFE8ECEA), fin: Color(0xFF9AA4A8), dorsal: 0.4),
  'kurodai': _F(len: 0.14, h: 0.07, back: Color(0xFF4E5660), belly: Color(0xFFA8B0B4), fin: Color(0xFF3E464E), dorsal: 0.6),
  'mebaru': _F(len: 0.12, h: 0.055, back: Color(0xFF4A4A38), belly: Color(0xFFC8A890), fin: Color(0xFF6A5A48), dorsal: 0.6, eye: 0.16),
  'kasago': _F(len: 0.12, h: 0.055, back: Color(0xFF9A4A32), belly: Color(0xFFD8A080), fin: Color(0xFF8A4A32), dorsal: 0.7, eye: 0.13),
  'suzuki': _F(len: 0.18, h: 0.045, back: Color(0xFF6A7A84), belly: Color(0xFFEAEEEC), fin: Color(0xFF8A9498), dorsal: 0.6),
  'mahaze': _F(len: 0.12, h: 0.03, back: Color(0xFF9A8A5A), belly: Color(0xFFE0D4A8), fin: Color(0xFFA89A68), tail: 0.14, dorsal: 0.4, eye: 0.1),
  'nijimasu': _F(len: 0.15, h: 0.045, back: Color(0xFF6A7A62), belly: Color(0xFFEAE6DA), fin: Color(0xFFA8A488), dorsal: 0.4),
  'iwana': _F(len: 0.15, h: 0.036, back: Color(0xFF5A5A3E), belly: Color(0xFFD8CCA8), fin: Color(0xFFD88A4A), dorsal: 0.4),
};

const _genericPlants = <String, String>{
  'yamazakura': 'treeB|4A3830|7BA85A|F4C4D0|1.0|',
  'keyaki': 'tree|6A5A48|5E8F3A|-|1.15|',
  'kunugi': 'tree|55402C|5A8A34|-|1.0|',
  'shirakashi': 'tree|4A4036|2F5A34|-|0.95|',
  'sudajii': 'tree|4A4036|2A5A34|-|1.15|',
  'tabunoki': 'tree|5A4636|2F6A3A|-|1.1|',
  'yamaboushi': 'treeB|6A5A48|5E9A44|F6F6EE|0.9|',
  'mizuki': 'treeB|5A4A3A|5E9A44|F2F2E6|1.0|',
  'kobushi': 'treeB|6A5A48|6EA44A|F8F8F0|1.0|',
  'hakumokuren': 'treeB|7A6A58|5E9A44|FBFBF4|1.0|',
  'sarusuberi': 'shrub|B8A890|5E9A44|E8709A|1.0|',
  'kinmokusei': 'shrub|4A4036|2F6A3A|F0A030|1.0|',
  'yamatsutsuji': 'shrub|6A5A48|4F8A3A|E8503A|1.0|',
  'mitsubatsutsuji': 'shrub|6A5A48|5E9A44|C84A9A|1.0|',
  'yamabuki': 'shrub|7A9A44|5E9A44|F2C21A|0.9|',
  'yamahagi': 'shrub|7A6A48|5E9A44|C85A9A|1.0|',
  'enoki': 'tree|7A6A58|5E9A44|-|1.05|',
  'mukunoki': 'tree|6A5A48|4F8A3A|-|1.1|',
  'nanten': 'shrubF|7A6A48|3F7A3A|D83A2A|0.9|',
  'aoki': 'shrubF|4F7A3A|2F6A3A|D82A2A|1.0|',
  'hinoki': 'conifer|3A6A3A|7ABA70|-|1.0|',
  'akamatsu': 'pine|3A6A3A|7A5A3A|-|1.0|',
  'karamatsu': 'conifer|7AAA4A|C8D880|-|1.0|',
  'momi': 'conifer|2F5A44|6AAA8A|-|1.05|',
  'tsuga': 'conifer|2F5A3A|7AAA70|-|1.0|',
  'shirakanba': 'tree|EDEDE6|7ABA5A|-|0.9|',
  'mizunara': 'tree|4A4036|4F8A3A|-|1.2|',
  'tochinoki': 'tree|5A4A3A|5E9A44|-|1.25|',
  'ezomatsu': 'conifer|1F4A3A|5A9A80|-|1.1|',
  'todomatsu': 'conifer|2A5A44|6AAA8A|-|1.0|',
  'nanakamado': 'treeF|6A5A48|5E9A44|D8302A|0.9|',
  'dakekanba': 'tree|D8D4C4|6AA84A|-|0.85|',
  'shakunage': 'shrub|3A6A3A|2F6A3A|F4D8E4|1.0|',
  'katakuri': 'herb|C86AB0|5E7A5A|F8E8F0|0.8|l',
  'nirinsou': 'herb|F6F6F0|6EA44A|F2D24A|0.7|r',
  'sumire': 'herb|7A4AC8|5E9A44|F2E48A|0.5|s',
  'renge': 'herb|E88AB8|6EAA4A|F8E0EC|0.5|r',
  'hotarubukuro': 'herb|E8B4D0|5E9A44|F8F0F4|0.8|b',
  'yamayuri': 'herb|F8F4EC|4F8A3A|D8A030|1.2|l',
  'tsuyukusa': 'herb|3A6AE8|6EAA4A|F2D24A|0.4|s',
  'ominaeshi': 'spike|F2C21A|5E9A44|-|1.0|',
  'kikyo': 'herb|6A4AC8|5E9A44|C8B0F0|0.9|s',
  'fujibakama': 'spike|D8B0D8|5E9A44|-|1.0|',
  'nadeshiko': 'herb|E870A8|6EAA4A|F8D8E8|0.7|s',
  'yomogi': 'grass|6E9A4A|-|-|1.0|',
  'miyakozasa': 'grass|5E9A44|-|-|0.8|',
  'sakurasou': 'herb|E8709A|6EAA4A|F8D8E4|0.5|s',
  'rindo': 'herb|3A5AC8|5E9A44|8AA8F0|0.6|b',
  'kuzu': 'shrub|4F8A3A|4F8A3A|9A4AC8|1.0|',
  'hirugao': 'herb|F4B8D0|6EAA4A|F8F0F4|0.5|b',
  'kakitsubata': 'spike|5A3AC8|4F8A3A|-|1.0|',
  'mizubasho': 'herb|F8F8F2|5EAA4A|F2E48A|1.0|l',
  'hishi': 'floating|4F8A3A|F8F8F2|-|1.0|',
  'ukigusa': 'floating|5EAA4A|-|-|0.6|',
  'shidareyanagi': 'tree|6A5A44|7EB45A|-|1.1|',
  'nekoyanagi': 'shrub|8A7A58|8EBA6A|F2F0E8|0.8|',
  'mizosoba': 'herb|F4C8D8|5E9A44|F8F0F4|0.4|r',
  'ooyoshi': 'grass|9AAA5A|D8D0B0|-|1.2|',
  'hamaboufu': 'herb|F8F4E8|6EAA5A|F8F8F2|0.5|r',
  'hamahirugao': 'herb|F08AB8|5EAA5A|F8E8F0|0.4|b',
  'hamanasu': 'shrub|6A5A44|4F8A3A|E83A6A|0.9|',
  'hamayu': 'herb|F8F8F2|5EAA4A|F8E8F0|1.0|l',
  'tsuwabuki': 'herb|F2C21A|3F7A3A|D8A010|0.7|r',
  'wakame': 'seaweed|7A6A2A|-|-|1.0|',
  'makonbu': 'seaweed|5A4A22|-|-|1.2|',
  'hijiki': 'seaweed|4A3A1A|-|-|0.8|',
  'kobaikeisou': 'spike|F8F8F0|4F8A3A|-|1.2|',
  'hakusanichige': 'herb|F8F8F4|6EAA4A|F2D24A|0.5|r',
  'chingruma': 'herb|F8F8F2|5EAA4A|F2D24A|0.4|r',
  'kurumayuri': 'herb|F08A2A|4F8A3A|C85A1A|1.0|l',
  'reba': 'herb|F2C21A|5EAA4A|F8D24A|0.4|s',
};
