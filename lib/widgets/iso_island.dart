import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/creature.dart';
import '../models/env_param.dart';
import '../providers/conservation_provider.dart';
import 'species_models.dart';

const _gold = Color(0xFFE8B96A);

/// 地形（世界座標）は x, y とも -1.6〜1.6 の1枚の連続した地形。
/// 山 → 里山の森 → 川 → 池 → 海 がなだらかにつながり、「ステージ」はその一部分。
const isoLayout = [
  Habitat.forest,
  Habitat.pond,
  Habitat.river,
  Habitat.ocean,
  Habitat.mountainLow,
  Habitat.mountainMid,
  Habitat.mountainHigh,
];

/// ステージの範囲（世界座標）
const _stageRects = <Habitat, Rect>{
  Habitat.mountainHigh: Rect.fromLTRB(0.35, -1.55, 1.35, -0.8),
  Habitat.mountainMid: Rect.fromLTRB(-0.6, -1.55, 0.35, -0.8),
  Habitat.mountainLow: Rect.fromLTRB(-1.55, -1.5, -0.6, -0.75),
  Habitat.forest: Rect.fromLTRB(-1.58, -0.7, -0.45, 0.8),
  Habitat.pond: Rect.fromLTRB(0.7, -0.62, 1.55, 0.45),
  Habitat.river: Rect.fromLTRB(-0.35, -0.8, 0.55, 0.85),
  Habitat.ocean: Rect.fromLTRB(-1.55, 0.72, 1.55, 1.55),
};

/// 海の地形の高さを決めるための範囲（ステージの範囲とは別）
const _oceanBlend = Rect.fromLTRB(-1.55, 1.0, 1.55, 1.55);

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

const _seaLevel = 0.07;
const _riverTop = -0.82;
const _pondC = Offset(1.12, 0.0);
const _pondRx = 0.40, _pondRy = 0.32;
const _pondZ = 0.135;

/// 川の中心線・川幅・水面の高さ（山から海へ向かって下る）
double riverX(double y) => 0.02 + 0.11 * sin((y + 0.9) * 2.6);
double riverHalf(double y) => 0.085 + 0.075 * _smooth(-0.2, 0.9, y);
double riverWaterZ(double y) => _seaLevel + 0.22 * (1 - _smooth(-0.8, 0.9, y));

/// 海岸線（波打つ）
double shoreY(double x) => 0.93 + 0.05 * sin(x * 2.2 + 0.6);

bool _inSea(double x, double y) => y > shoreY(x);
bool _inRiver(double x, double y, [double m = 1.0]) =>
    y > _riverTop && y < shoreY(riverX(y)) + 0.02 && (x - riverX(y)).abs() < riverHalf(y) * m;
bool _inPond(double x, double y, [double m = 0.9]) {
  final a = (x - _pondC.dx) / _pondRx, b = (y - _pondC.dy) / _pondRy;
  return a * a + b * b < m * m;
}

/// 水面の高さ（水の上ならその高さ、陸なら null）
double? _waterZ(double x, double y) {
  if (_inSea(x, y)) return _seaLevel;
  if (_inRiver(x, y, 1.0)) return riverWaterZ(y);
  if (_inPond(x, y, 0.95)) return _pondZ;
  return null;
}

/// 連続した地形の高さ・色。標高（山の3ステージ）が変わると作り直す。
class TerrainField {
  static const g = 48; // 格子の分割数
  static const size = 3.2;

  final double zLow, zMid, zHigh, snowH;
  final String key;
  late final Float64List hs; // (g+1)*(g+1)
  late final Int32List cols; // 頂点の色（ARGB）

  TerrainField._(double eLow, double eMid, double eHigh, this.key)
      : zLow = _zOf(eLow),
        zMid = _zOf(eMid),
        zHigh = _zOf(eHigh),
        snowH = eHigh < 1800 ? 9.0 : 0.6 - (eHigh - 1800) / 1200 * 0.1 {
    _build();
  }

  static double _zOf(double e) => 0.1 + e / 3000 * 0.55;

  static final _cache = <String, TerrainField>{};

  static TerrainField forState(ConservationState s) {
    final l = s.areas[Habitat.mountainLow]![EnvParam.elevation];
    final m = s.areas[Habitat.mountainMid]![EnvParam.elevation];
    final h = s.areas[Habitat.mountainHigh]![EnvParam.elevation];
    final k = '${l.round()}|${m.round()}|${h.round()}';
    return _cache.putIfAbsent(k, () => TerrainField._(l, m, h, k));
  }

  /// 地形の高さ
  double height(double x, double y) {
    var sw = 0.05, sz = 0.05 * 0.13, wm = 0.0, wmz = 0.0;
    void add(Rect r, double z, double sigma, {bool mtn = false}) {
      final dx = max(max(r.left - x, 0.0), x - r.right);
      final dy = max(max(r.top - y, 0.0), y - r.bottom);
      final w = exp(-(dx * dx + dy * dy) / (sigma * sigma));
      sw += w;
      sz += w * z;
      if (mtn) {
        wm += w;
        wmz += w * z;
      }
    }

    add(_stageRects[Habitat.mountainHigh]!, zHigh, 0.32, mtn: true);
    add(_stageRects[Habitat.mountainMid]!, zMid, 0.32, mtn: true);
    add(_stageRects[Habitat.mountainLow]!, zLow, 0.32, mtn: true);
    add(_stageRects[Habitat.forest]!, 0.2, 0.3);
    add(_stageRects[Habitat.pond]!, 0.14, 0.3);
    add(_stageRects[Habitat.river]!, 0.12, 0.25);
    add(_oceanBlend, 0.05, 0.2);
    var z = sz / sw;

    // 山の起伏：尾根と、高さの違う峰
    final mf = wm / sw;
    final zm = wm > 1e-6 ? wmz / wm : 0.0;
    final a = sin(x * 5.1 + sin(y * 3.3) * 1.4), b = sin(y * 4.4 + x * 2.2 + 1.7), c = sin((x + y) * 7.3);
    final ridge = 0.5 + 0.3 * (1 - a.abs()) + 0.2 * (1 - b.abs()) + 0.06 * c;
    z += mf * (ridge - 0.62) * zm * 0.9;
    double bump(double cx, double cy, double r) {
      final dx = x - cx, dy = y - cy;
      return exp(-(dx * dx + dy * dy) / (r * r));
    }

    z += mf *
        (bump(0.85, -1.28, 0.3) * zHigh * 0.55 +
            bump(1.15, -1.05, 0.2) * zHigh * 0.25 +
            bump(0.0, -1.3, 0.3) * zMid * 0.35 +
            bump(-1.0, -1.15, 0.3) * zLow * 0.3);

    // 川の谷：山のふもとから海へ、川面は下りながら続く
    final sy = shoreY(riverX(y));
    final wr = _smooth(_riverTop - 0.08, _riverTop + 0.06, y) * (1 - _smooth(sy - 0.04, sy + 0.1, y));
    if (wr > 0) {
      final d = (x - riverX(y)).abs();
      final hw = riverHalf(y);
      final wz = riverWaterZ(y);
      final bed = wz - 0.03;
      final bank = _smooth(hw * 0.85, hw + 0.2, d);
      final target = _lerp(bed, min(z, wz + 0.12), bank);
      final fd = 1 - _smooth(hw + 0.2, hw + 0.55, d);
      z = _lerp(z, target, wr * fd);
    }

    // 池の窪み
    final pa = (x - _pondC.dx) / _pondRx, pb = (y - _pondC.dy) / _pondRy;
    final dp = sqrt(pa * pa + pb * pb);
    if (dp < 1.6) {
      final bank = _smooth(0.85, 1.3, dp);
      final bed = _pondZ - 0.03;
      final target = _lerp(bed, min(z, _pondZ + 0.06), bank);
      z = _lerp(z, target, 1 - _smooth(1.2, 1.6, dp));
    }

    // 海：砂浜から沖へ緩やかに深くなる
    final dsea = y - shoreY(x);
    if (dsea > -0.12) {
      z = _lerp(z, min(z, 0.11), _smooth(-0.12, 0.0, dsea));
    }
    if (dsea > 0) {
      z = _lerp(z, _seaLevel - 0.07, _smooth(0.0, 0.28, dsea));
    }
    return z.clamp(-0.02, 1.0).toDouble();
  }

  static const _ramp = <(double, int)>[
    (0.00, 0xFF9DB45A),
    (0.14, 0xFF7FA84C),
    (0.22, 0xFF4F8A3A),
    (0.32, 0xFF2F5A34),
    (0.42, 0xFF47663A),
    (0.50, 0xFF7A8450),
    (0.58, 0xFF88867A),
    (0.80, 0xFF9A988E),
  ];

  static Color _rampColor(double h) {
    if (h <= _ramp.first.$1) return Color(_ramp.first.$2);
    for (var i = 1; i < _ramp.length; i++) {
      if (h <= _ramp[i].$1) {
        final t = (h - _ramp[i - 1].$1) / (_ramp[i].$1 - _ramp[i - 1].$1);
        return Color.lerp(Color(_ramp[i - 1].$2), Color(_ramp[i].$2), t)!;
      }
    }
    return Color(_ramp.last.$2);
  }

  Color _baseColor(double x, double y, double h, double nz) {
    if (_inSea(x, y)) {
      final d = (y - shoreY(x)).clamp(0.0, 0.4);
      return Color.lerp(const Color(0xFFCDBF96), const Color(0xFF12325C), _smooth(0, 0.3, d))!;
    }
    if (_inRiver(x, y, 1.15) || _inPond(x, y, 1.0)) return const Color(0xFF2F5C68);
    var land = _rampColor(h);
    // 里（池のまわり）は、明るい草地・畑の色
    final vr = _stageRects[Habitat.pond]!;
    final vd = max(max(vr.left - x, 0.0), x - vr.right) + max(max(vr.top - y, 0.0), y - vr.bottom);
    land = Color.lerp(land, const Color(0xFFB8C86C), 0.4 * (1 - _smooth(0.0, 0.35, vd)))!;
    // 砂浜
    final sd = shoreY(x) - y;
    if (sd < 0.1) {
      land = Color.lerp(const Color(0xFFD8C9A0), land, _smooth(0.0, 0.1, sd))!;
    }
    // 川・池のほとりの湿った土
    final rd = _inRiver(x, y, 1.9) ? 1.0 : 0.0;
    if (rd > 0) land = Color.lerp(land, const Color(0xFF6E8A4A), 0.25)!;
    // 雪
    if (h > snowH) {
      land = Color.lerp(land, const Color(0xFFEFF4F8), _smooth(snowH, snowH + 0.05, h) * _smooth(0.55, 0.85, nz))!;
    }
    return land;
  }

  void _build() {
    const n = g + 1;
    const d = size / g;
    hs = Float64List(n * n);
    cols = Int32List(n * n);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        hs[i * n + j] = height(-size / 2 + i * d, -size / 2 + j * d);
      }
    }
    double hAt(int i, int j) => hs[i.clamp(0, g) * n + j.clamp(0, g)];
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final x = -size / 2 + i * d, y = -size / 2 + j * d;
        final h = hAt(i, j);
        final hx = (hAt(i + 1, j) - hAt(i - 1, j)) / (2 * d);
        final hy = (hAt(i, j + 1) - hAt(i, j - 1)) / (2 * d);
        final nl = sqrt(hx * hx * 1.96 + hy * hy * 1.96 + 1);
        final nx = -hx * 1.4 / nl, ny = -hy * 1.4 / nl, nz = 1 / nl;
        final lit = (nx * -0.5 + ny * 0.5 + nz * 0.75) / 1.0677;
        final base = _baseColor(x, y, h, nz);
        final noise = (sin(x * 41 + y * 17) + sin(x * 23 - y * 37)) * 0.5;
        final k = (0.45 + 0.85 * lit.clamp(0.0, 1.0)) * (1 + 0.05 * noise);
        int ch(double v) => (v * 255 * k).round().clamp(0, 255);
        cols[i * n + j] = 0xFF000000 | (ch(base.r) << 16) | (ch(base.g) << 8) | ch(base.b);
      }
    }
  }

  double heightAt(double x, double y) {
    const n = g + 1;
    final fx = ((x + size / 2) / size * g).clamp(0.0, g - 0.001);
    final fy = ((y + size / 2) / size * g).clamp(0.0, g - 0.001);
    final i = fx.floor(), j = fy.floor();
    final tx = fx - i, ty = fy - j;
    final h00 = hs[i * n + j], h10 = hs[(i + 1) * n + j], h01 = hs[i * n + j + 1], h11 = hs[(i + 1) * n + j + 1];
    return _lerp(_lerp(h00, h10, tx), _lerp(h01, h11, tx), ty);
  }
}

/// 水の上なら水面、陸なら地形の高さ
double surfaceZ(TerrainField tf, double x, double y) => _waterZ(x, y) ?? tf.heightAt(x, y);

/// ステージ内の位置 (u,v は 0〜1) を、世界座標に変える。水のステージは水面の上に置く
Offset stagePoint(Habitat h, double u, double v) {
  final r = _stageRects[h]!;
  switch (h) {
    case Habitat.pond:
      return Offset(_pondC.dx + (u - 0.5) * 2 * 0.8 * _pondRx, _pondC.dy + (v - 0.5) * 2 * 0.8 * _pondRy);
    case Habitat.river:
      final y = -0.7 + v * 1.45;
      return Offset(riverX(y) + (u - 0.5) * riverHalf(y) * 1.4, y);
    case Habitat.ocean:
      final x = -1.45 + u * 2.9;
      return Offset(x, shoreY(x) + 0.12 + v * 0.35);
    default:
      return Offset(r.left + (0.08 + u * 0.84) * r.width, r.top + (0.08 + v * 0.84) * r.height);
  }
}

/// ワールド座標(x,y,z)→画面座標。[focus] を指定すると、そのステージを大きく映す。
class IsoView {
  static const double ky = 0.6; // 縦方向の圧縮（大きいほど真上に近い）

  final Size size;
  final double angle;
  final Habitat? focus;
  final double zoom; // 拡大率（1.0 = 標準）
  final Offset pan; // 画面上の平行移動
  late final double s, cx, cy, ca, sa, ox, oy;

  IsoView(this.size, this.angle, {this.focus, this.zoom = 1, this.pan = Offset.zero}) {
    ca = cos(angle);
    sa = sin(angle);
    if (focus == null) {
      ox = 0;
      oy = 0;
      s = (size.width * 0.5 - 8) / 2.95 * zoom;
      cy = size.height * 0.5 + pan.dy;
    } else {
      final r = _stageRects[focus!]!;
      ox = r.center.dx;
      oy = r.center.dy;
      final k = max(r.width, r.height) * 0.62 + 0.4;
      s = (size.width * 0.5 - 8) / k * zoom;
      cy = size.height * 0.58 + pan.dy;
    }
    cx = size.width / 2 + pan.dx;
  }

  Offset p(double x, double y, [double z = 0]) {
    final dx = x - ox, dy = y - oy;
    final xr = dx * ca - dy * sa;
    final yr = dx * sa + dy * ca;
    return Offset(cx + (xr - yr) * 0.866 * s, cy + (xr + yr) * ky * s - z * s);
  }

  double depth(double x, double y) {
    final dx = x - ox, dy = y - oy;
    return (dx * ca - dy * sa) + (dx * sa + dy * ca);
  }

  /// ステージの範囲（四角）
  static Rect stageRect(Habitat h) => _stageRects[h]!;

  Path stagePath(Habitat h, [double z = 0.15]) {
    final r = _stageRects[h]!;
    return Path()
      ..moveTo(p(r.left, r.top, z).dx, p(r.left, r.top, z).dy)
      ..lineTo(p(r.right, r.top, z).dx, p(r.right, r.top, z).dy)
      ..lineTo(p(r.right, r.bottom, z).dx, p(r.right, r.bottom, z).dy)
      ..lineTo(p(r.left, r.bottom, z).dx, p(r.left, r.bottom, z).dy)
      ..close();
  }

  /// タップ位置のステージ（手前を優先）
  Habitat? hit(Offset pos) {
    final order = [...isoLayout]
      ..sort((a, b) {
        final ra = _stageRects[a]!.center, rb = _stageRects[b]!.center;
        return depth(rb.dx, rb.dy).compareTo(depth(ra.dx, ra.dy));
      });
    for (final h in order) {
      final z = h.isMountain ? 0.35 : 0.12;
      if (stagePath(h, z).contains(pos)) return h;
    }
    return null;
  }
}

/// ステージ内の各種の位置と、混み具合に応じた大きさの倍率
class _Layout {
  final Map<String, Offset> pos;
  final double scale;
  const _Layout(this.pos, this.scale);
}

class _Item {
  final double depth;
  final void Function() draw;
  _Item(this.depth, this.draw);
}

class IsoIslandPainter extends CustomPainter {
  final ConservationState state;
  final List<Creature> creatures;
  final ConservationNotifier notifier;
  final double aliveRatio;
  final double t;
  final double angle;
  final Habitat? focus;
  final double zoom;
  final Offset pan;

  IsoIslandPainter({
    required this.state,
    required this.creatures,
    required this.notifier,
    required this.aliveRatio,
    required this.t,
    required this.angle,
    this.focus,
    this.zoom = 1,
    this.pan = Offset.zero,
  });

  late Canvas _c;
  late IsoView _v;

  late Size _size;
  late TerrainField _tf;

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    _size = size;
    _v = IsoView(size, angle, focus: focus, zoom: zoom, pan: pan);
    final tf = TerrainField.forState(state);
    _tf = tf;

    _bokeh(size);
    _walls(tf);
    _c.drawVertices(_terrainVertices(tf), BlendMode.dst, Paint());
    _waters(tf);

    // ステージの中身（木・岩・花・生き物・家）を、奥から手前へ
    final items = <_Item>[];
    for (final h in (focus != null ? [focus!] : isoLayout)) {
      _stageItems(items, h);
    }
    items.sort((a, b) => a.depth.compareTo(b.depth));
    for (final it in items) {
      it.draw();
    }

    _fireflies();
    if (focus != null) {
      _dim(focus!);
    } else {
      for (final h in isoLayout) {
        _label(h);
      }
    }
  }

  // ---- 連続した地形 ---------------------------------------------------------

  static ui.Vertices? _vCache;
  static String? _vKey;

  /// 地形の三角形（頂点ごとの色でなめらかに陰影がつく）。視点が変わったときだけ作り直す
  ui.Vertices _terrainVertices(TerrainField tf) {
    final key =
        '${tf.key}|${_v.ca.toStringAsFixed(5)}|${_v.sa.toStringAsFixed(5)}|${_v.s.toStringAsFixed(3)}|${_v.cx.toStringAsFixed(2)}|${_v.cy.toStringAsFixed(2)}|${_v.ox.toStringAsFixed(3)}|${_v.oy.toStringAsFixed(3)}';
    if (_vKey == key && _vCache != null) return _vCache!;
    const g = TerrainField.g, n = g + 1;
    const d = TerrainField.size / g;
    const h0 = -TerrainField.size / 2;
    final sx = Float32List(n * n), sy = Float32List(n * n);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final o = _v.p(h0 + i * d, h0 + j * d, tf.hs[i * n + j]);
        sx[i * n + j] = o.dx;
        sy[i * n + j] = o.dy;
      }
    }
    final order = List<int>.generate(g * g, (k) => k);
    final depthKey = Float64List(g * g);
    for (var k = 0; k < g * g; k++) {
      final i = k ~/ g, j = k % g;
      depthKey[k] = _v.depth(h0 + (i + 0.5) * d, h0 + (j + 0.5) * d) + 0.4 * tf.hs[i * n + j];
    }
    order.sort((a, b) => depthKey[a].compareTo(depthKey[b]));
    final pos = Float32List(g * g * 12);
    final col = Int32List(g * g * 6);
    var pi2 = 0, ci = 0;
    void put(int idx) {
      pos[pi2++] = sx[idx];
      pos[pi2++] = sy[idx];
      col[ci++] = tf.cols[idx];
    }

    for (final k in order) {
      final i = k ~/ g, j = k % g;
      final a = i * n + j, b = (i + 1) * n + j, c = (i + 1) * n + j + 1, dd = i * n + j + 1;
      put(a);
      put(b);
      put(c);
      put(a);
      put(c);
      put(dd);
    }
    final v = ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: col);
    _vCache?.dispose();
    _vCache = v;
    _vKey = key;
    return v;
  }

  /// 地形のふち：苔むした石積みの壁（見えている側面だけ）
  void _walls(TerrainField tf) {
    const g = TerrainField.g;
    const d = TerrainField.size / g;
    const h0 = -TerrainField.size / 2;
    const bottom = -0.16;
    const palette = [Color(0xFF8A7A62), Color(0xFF7C6C58), Color(0xFF9A8A70), Color(0xFF6E6A5E), Color(0xFF8C8068)];
    final edges = [
      (h0, h0, 1.0, 0.0, 0.0, -1.0, 1),
      (-h0, h0, 0.0, 1.0, 1.0, 0.0, 2),
      (-h0, -h0, -1.0, 0.0, 0.0, 1.0, 3),
      (h0, -h0, 0.0, -1.0, -1.0, 0.0, 4),
    ];
    for (final e in edges) {
      if (!_faceVisible(e.$5, e.$6)) continue;
      final nx = e.$5 * _v.ca - e.$6 * _v.sa;
      final ny = e.$5 * _v.sa + e.$6 * _v.ca;
      final k = 0.62 - 0.22 * (nx - ny) / 1.414;
      final rng = Random(e.$7 * 53);
      for (var s = 0; s < g; s++) {
        final x0 = e.$1 + e.$3 * d * s, y0 = e.$2 + e.$4 * d * s;
        final x1 = x0 + e.$3 * d, y1 = y0 + e.$4 * d;
        final zt0 = surfaceZ(tf, x0, y0), zt1 = surfaceZ(tf, x1, y1);
        for (var r = 0; r < 3; r++) {
          final f0 = r / 3.0, f1 = (r + 1) / 3.0;
          final pts = [
            _v.p(x0, y0, _lerp(bottom, zt0, f0)),
            _v.p(x1, y1, _lerp(bottom, zt1, f0)),
            _v.p(x1, y1, _lerp(bottom, zt1, f1)),
            _v.p(x0, y0, _lerp(bottom, zt0, f1)),
          ];
          _quad(pts, _shade(palette[rng.nextInt(palette.length)], k * (0.9 + rng.nextDouble() * 0.2)),
              edge: Colors.black.withValues(alpha: 0.28));
        }
        if (rng.nextDouble() < 0.3) {
          _c.drawCircle(_v.p(x0, y0, zt0), _v.s * (0.012 + rng.nextDouble() * 0.014),
              Paint()..color = Color.lerp(const Color(0xFF4F8A2E), const Color(0xFF9CC050), rng.nextDouble())!);
        }
      }
    }
  }

  // ---- 水（海・川・池） -----------------------------------------------------

  List<Offset> _pebblePoints(int seed, int n, bool Function(double, double) inside, Rect bounds) {
    final rng = Random(seed);
    final out = <Offset>[];
    var tries = 0;
    while (out.length < n && tries++ < n * 12) {
      final x = bounds.left + rng.nextDouble() * bounds.width;
      final y = bounds.top + rng.nextDouble() * bounds.height;
      if (inside(x, y)) out.add(_v.p(x, y, _tf.heightAt(x, y) + 0.002));
    }
    return out;
  }

  void _waterBody(List<Offset> poly, Offset center, double radius, Color deep, Color shallow, int seed,
      List<Offset> pebbles) {
    final path = Path()..moveTo(poly.first.dx, poly.first.dy);
    for (final o in poly.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    path.close();
    _c.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [deep.withValues(alpha: 0.9), Color.lerp(deep, shallow, 0.6)!.withValues(alpha: 0.86), shallow.withValues(alpha: 0.82)],
            stops: const [0, 0.6, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)));
    _c.save();
    _c.clipPath(path);
    // 底の小石
    final rng = Random(seed);
    for (final o in pebbles) {
      final col = [const Color(0xFFB8A888), const Color(0xFF8A8478), const Color(0xFFC8B898), const Color(0xFF6E6A5E)][rng.nextInt(4)];
      _c.drawOval(Rect.fromCenter(center: o, width: 3 + rng.nextDouble() * 5, height: 2 + rng.nextDouble() * 2.4),
          Paint()..color = col.withValues(alpha: 0.5));
    }
    // 広がるさざ波と、水面のきらめき
    for (var k = 0; k < 3; k++) {
      final f = ((t * 0.12 + k / 3 + seed * 0.07) % 1.0);
      final b = path.getBounds();
      final c = Offset(b.left + b.width * (0.25 + 0.5 * ((seed + k * 3) % 5) / 5), b.top + b.height * (0.3 + 0.4 * ((k * 5 + seed) % 4) / 4));
      _c.drawOval(Rect.fromCenter(center: c, width: _v.s * 0.4 * f, height: _v.s * 0.2 * f),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.28 * (1 - f)));
    }
    final b = path.getBounds();
    for (var k = 0; k < 10; k++) {
      final o = Offset(b.left + rng.nextDouble() * b.width, b.top + rng.nextDouble() * b.height);
      final a = (0.5 + 0.5 * sin(t * 2.2 + k * 1.9)).clamp(0.0, 1.0);
      _c.drawCircle(o, 1.1, Paint()..color = Colors.white.withValues(alpha: 0.6 * a));
    }
    _c.restore();
    // 水ぎわのふち
    _c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = Colors.white.withValues(alpha: 0.18));
  }

  void _waters(TerrainField tf) {
    // 海
    final sea = <Offset>[
      for (var i = 0; i <= 40; i++)
        _v.p(-1.6 + 3.2 * i / 40, shoreY(-1.6 + 3.2 * i / 40) + 0.004, _seaLevel),
      _v.p(1.6, 1.6, _seaLevel),
      _v.p(-1.6, 1.6, _seaLevel),
    ];
    _waterBody(sea, _v.p(0, 1.35, _seaLevel), _v.s * 1.9, const Color(0xFF0B3466), const Color(0xFF4C93BE), 11,
        _pebblePoints(11, 14, (x, y) => _inSea(x, y) && y < shoreY(x) + 0.22, const Rect.fromLTRB(-1.6, 0.8, 1.6, 1.4)));
    // 沖のうねり（海岸線に沿った波）
    for (var k = 0; k < 6; k++) {
      final path = Path();
      var started = false;
      for (var i = 0; i <= 30; i++) {
        final x = -1.6 + 3.2 * i / 30;
        final y = shoreY(x) + 0.05 + k * 0.1 + 0.014 * sin(x * 7 + t * 0.9 + k * 1.3);
        if (y > 1.6) continue;
        final o = _v.p(x, y, _seaLevel + 0.002);
        if (!started) {
          path.moveTo(o.dx, o.dy);
          started = true;
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      _c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.1));
    }
    // 岸に寄せる白波
    final foam = Path();
    for (var i = 0; i <= 60; i++) {
      final x = -1.6 + 3.2 * i / 60;
      final o = _v.p(x, shoreY(x) + 0.01 + 0.012 * sin(x * 9 + t * 1.6), _seaLevel + 0.003);
      i == 0 ? foam.moveTo(o.dx, o.dy) : foam.lineTo(o.dx, o.dy);
    }
    _c.drawPath(
        foam,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = Colors.white.withValues(alpha: 0.38));

    // 川（山から海へ。川面は下りながら続く）
    final left = <Offset>[], right = <Offset>[];
    for (var y = _riverTop; y <= shoreY(riverX(0.9)) + 0.03; y += 0.05) {
      final x = riverX(y), hw = riverHalf(y), z = riverWaterZ(y);
      left.add(_v.p(x - hw, y, z));
      right.add(_v.p(x + hw, y, z));
    }
    _waterBody([...left, ...right.reversed], _v.p(0, 0.1, 0.15), _v.s * 1.0, const Color(0xFF1B5A70), const Color(0xFF5FB0B8), 23,
        _pebblePoints(23, 26, (x, y) => _inRiver(x, y), const Rect.fromLTRB(-0.3, -0.8, 0.5, 1.0)));
    // 川の流れ
    for (final lane in const [-0.55, 0.0, 0.55]) {
      for (var k = 0; k < 9; k++) {
        final y0 = _riverTop + ((k / 9.0 + t * 0.045 + lane * 0.1) % 1.0) * (shoreY(riverX(0.9)) - _riverTop);
        final pts = [for (final yy in [y0, y0 + 0.05, y0 + 0.1]) _v.p(riverX(yy) + lane * riverHalf(yy), yy, riverWaterZ(yy) + 0.003)];
        _c.drawPath(
            Path()
              ..moveTo(pts[0].dx, pts[0].dy)
              ..quadraticBezierTo(pts[1].dx, pts[1].dy, pts[2].dx, pts[2].dy),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = Colors.white.withValues(alpha: 0.32));
      }
    }
    // 川の源：中腹から落ちる小さな滝
    for (var k = 0; k < 7; k++) {
      final x = riverX(-0.9) + (k - 3) * 0.014;
      final y0 = -1.08 + ((t * 0.5 + k * 0.37) % 1.0) * 0.24;
      _c.drawLine(_v.p(x, y0, tf.heightAt(x, y0) + 0.006), _v.p(x, y0 + 0.05, tf.heightAt(x, y0 + 0.05) + 0.006),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.85)
            ..strokeWidth = 1.5);
    }
    for (var k = 0; k < 5; k++) {
      _c.drawCircle(_v.p(riverX(-0.84) + (k - 2) * 0.02, -0.84 + sin(t * 5 + k) * 0.004, riverWaterZ(-0.82) + 0.008), 2.2,
          Paint()..color = Colors.white.withValues(alpha: 0.7));
    }

    // 池（里の池）
    final pond = <Offset>[
      for (var i = 0; i < 40; i++)
        _v.p(_pondC.dx + cos(i / 40 * 2 * pi) * _pondRx * 0.95, _pondC.dy + sin(i / 40 * 2 * pi) * _pondRy * 0.95, _pondZ),
    ];
    _waterBody(pond, _v.p(_pondC.dx, _pondC.dy, _pondZ), _v.s * 0.55, const Color(0xFF14506E), const Color(0xFF58A8B0), 31,
        _pebblePoints(31, 22, (x, y) => _inPond(x, y, 0.93), Rect.fromCenter(center: _pondC, width: _pondRx * 2, height: _pondRy * 2)));
  }

  // ---- ステージの中身 ------------------------------------------------------

  // ---- 生き物の配置（重ならず、ごちゃつかないように） ---------------------------

  /// 水の植物（水中・水面に生える）。それ以外の植物は、川辺・浜・池のほとりでは陸側に置く
  static const _waterPlants = {'suiren', 'hasu', 'kohone', 'amamo', 'mangrove'};

  static bool _placeOnLand(Habitat h, Creature c) =>
      h.isLand ||
      c.type == CreatureType.animal ||
      (c.type == CreatureType.plant && !_waterPlants.contains(c.id));

  static Offset _samplePoint(Habitat h, bool land, Random rng) {
    switch (h) {
      case Habitat.river:
        final y = -0.66 + rng.nextDouble() * 1.4;
        if (land) {
          final side = rng.nextBool() ? 1.0 : -1.0;
          return Offset(riverX(y) + side * (riverHalf(y) + 0.06 + rng.nextDouble() * 0.13), y);
        }
        return Offset(riverX(y) + (rng.nextDouble() - 0.5) * riverHalf(y) * 1.5, y);
      case Habitat.pond:
        final a = rng.nextDouble() * 2 * pi;
        final f = land ? 1.08 + rng.nextDouble() * 0.28 : sqrt(rng.nextDouble()) * 0.82;
        return Offset(_pondC.dx + cos(a) * _pondRx * f, _pondC.dy + sin(a) * _pondRy * f);
      case Habitat.ocean:
        final x = -1.45 + rng.nextDouble() * 2.9;
        return land
            ? Offset(x, shoreY(x) - 0.05 - rng.nextDouble() * 0.2)
            : Offset(x, shoreY(x) + 0.12 + rng.nextDouble() * 0.38);
      default:
        final r = _stageRects[h]!;
        return Offset(r.left + (0.06 + rng.nextDouble() * 0.88) * r.width, r.top + (0.06 + rng.nextDouble() * 0.88) * r.height);
    }
  }

  static bool _insideDomain(Habitat h, bool land, Offset p) {
    final x = p.dx, y = p.dy;
    switch (h) {
      case Habitat.river:
        if (y < -0.68 || y > shoreY(riverX(y)) - 0.1) return false;
        final d = (x - riverX(y)).abs(), hw = riverHalf(y);
        return land ? (d > hw + 0.04 && d < hw + 0.3) : d < hw * 0.8;
      case Habitat.pond:
        final a = (x - _pondC.dx) / _pondRx, b = (y - _pondC.dy) / _pondRy;
        final f = sqrt(a * a + b * b);
        // 家の前（池の北側）は避ける
        return land ? (f > 1.05 && f < 1.45 && !(y < -0.3 && (x - _pondC.dx).abs() < 0.34)) : f < 0.85;
      case Habitat.ocean:
        if (x.abs() > 1.5) return false;
        return land
            ? (y < shoreY(x) - 0.03 && y > shoreY(x) - 0.28)
            : (y > shoreY(x) + 0.1 && y < shoreY(x) + 0.55);
      default:
        final r = _stageRects[h]!;
        return x > r.left + 0.03 && x < r.right - 0.03 && y > r.top + 0.03 && y < r.bottom - 0.03 && _waterZ(x, y) == null;
    }
  }

  /// 領域の使える面積（世界座標の面積）
  static double _domainArea(Habitat h, bool land) {
    switch (h) {
      case Habitat.river:
        return land ? 0.4 : 0.32;
      case Habitat.pond:
        return land ? 0.3 : 0.3;
      case Habitat.ocean:
        return land ? 0.55 : 0.95;
      default:
        final r = _stageRects[h]!;
        return r.width * r.height * 0.85;
    }
  }

  static final _layoutCache = <String, _Layout>{};

  /// ステージ内の全種の位置。大きさに応じて間隔をあけ、混み合うほど小さくして、重ならないようにする
  static _Layout layoutStage(Habitat h, List<Creature> list) {
    final key = '${h.index}|${list.map((c) => c.id).join(',')}';
    return _layoutCache.putIfAbsent(key, () {
      final pos = <String, Offset>{};
      final land = <String, bool>{};
      final rad = <String, double>{};
      for (final c in list) {
        final l = _placeOnLand(h, c);
        land[c.id] = l;
        rad[c.id] = SpeciesRenderer.radius(c) * 0.9;
        final rng = Random(h.index * 977 + c.id.hashCode);
        var p = _samplePoint(h, l, rng);
        for (var k = 0; k < 24 && !_insideDomain(h, l, p); k++) {
          p = _samplePoint(h, l, rng);
        }
        pos[c.id] = p;
      }
      // 混み合うほど小さくする（陸と水で別々に面積を見て、小さいほうに合わせる）
      var scale = 1.0;
      for (final isLand in [true, false]) {
        final group = list.where((c) => land[c.id] == isLand).toList();
        if (group.isEmpty) continue;
        final need = group.fold<double>(0, (a, c) => a + pi * rad[c.id]! * rad[c.id]!);
        scale = min(scale, sqrt(0.5 * _domainArea(h, isLand) / need));
      }
      scale = scale.clamp(0.35, 1.0).toDouble();
      // 押し合って、重なりをほどく
      for (var it = 0; it < 70; it++) {
        for (var i = 0; i < list.length; i++) {
          for (var j = i + 1; j < list.length; j++) {
            final a = list[i], b = list[j];
            if (land[a.id] != land[b.id]) continue;
            final pa = pos[a.id]!, pb = pos[b.id]!;
            final d = (pa - pb).distance;
            final minD = (rad[a.id]! + rad[b.id]!) * scale;
            if (d < minD && d > 1e-6) {
              final push = (pb - pa) / d * ((minD - d) / 2);
              final na = pa - push, nb = pb + push;
              if (_insideDomain(h, land[a.id]!, na)) pos[a.id] = na;
              if (_insideDomain(h, land[b.id]!, nb)) pos[b.id] = nb;
            }
          }
        }
      }
      return _Layout(pos, scale);
    });
  }

  /// 動物はゆっくり動く（植物は動かない）
  static Offset _drift(Habitat h, Creature c, Offset base, double t) {
    final ph = (c.id.hashCode.abs() % 628) / 100.0;
    switch (c.type) {
      case CreatureType.plant:
        return base;
      case CreatureType.bird:
        return base + Offset(cos(t * 0.5 + ph), sin(t * 0.7 + ph)) * 0.035;
      case CreatureType.fish:
        return base + Offset(sin(t * 0.4 + ph) * 0.05, cos(t * 0.3 + ph) * 0.015);
      case CreatureType.animal:
        return base + Offset(cos(t * 0.25 + ph), sin(t * 0.3 + ph)) * 0.02;
    }
  }

  void _addStageCreatures(List<_Item> items, Habitat h) {
    final shown = habitatSpecies(h, state, notifier, creatures);
    final lay = layoutStage(h, shown);
    for (final c in shown) {
      final pop = state.population[c.id] ?? 0;
      final alpha = presenceAlpha(c, t, state.turn, pop);
      if (alpha <= 0) continue;
      final p = _drift(h, c, lay.pos[c.id]!, t);
      final x = p.dx, y = p.dy;
      final z = surfaceZ(_tf, x, y);
      final fit = notifier.suitability(c, h, s: state).clamp(0.0, 1.0).toDouble();
      items.add(_Item(_v.depth(x, y), () {
        final ground = _v.p(x, y, z);
        _withOpacity(alpha, ground, () {
          if (focus != null) {
            _speciesObject(c, ground, h, lay.scale);
          } else {
            _overviewCreature(c, ground, fit, pop, lay.scale, x, y, z);
          }
        });
      }));
    }
  }

  void _overviewCreature(Creature c, Offset ground, double fit, int pop, double scale, double x, double y, double z) {
    final lift = c.type == CreatureType.bird ? (0.2 * _v.s * scale) : 0.0;
    if (c.endangered) _rareAura(ground, SpeciesRenderer.centerLift(c) * _v.s * scale + lift);
    switch (c.type) {
      case CreatureType.plant:
        SpeciesRenderer.paint(_c, c, ground, _v.s, t, fit: fit, pop: pop, boost: scale);
      case CreatureType.bird:
        _shadow(ground, 0.03 * scale);
        SpeciesRenderer.paint(_c, c, ground - Offset(0, lift), _v.s, t, fit: fit, pop: pop, boost: scale);
      case CreatureType.fish:
        SpeciesRenderer.paint(_c, c, _v.p(x, y, z - 0.015), _v.s, t, fit: fit, pop: pop, boost: scale);
      case CreatureType.animal:
        SpeciesRenderer.paint(_c, c, ground, _v.s, t, fit: fit, pop: pop, boost: scale);
    }
  }

  /// 画面上のモデル位置（描画とタップ判定で共通）: (種, 当たり判定の中心, 半径)
  static List<(Creature, Offset, double)> medallionPlacements(
      IsoView v,
      Habitat h,
      ConservationState state,
      ConservationNotifier notifier,
      List<Creature> creatures,
      double t) {
    final tf = TerrainField.forState(state);
    final shown = habitatSpecies(h, state, notifier, creatures);
    final lay = layoutStage(h, shown);
    final out = <(Creature, Offset, double)>[];
    for (final c in shown) {
      if (presenceAlpha(c, t, state.turn, state.population[c.id] ?? 0) <= 0.3) continue;
      final p = _drift(h, c, lay.pos[c.id]!, t);
      final ground = v.p(p.dx, p.dy, surfaceZ(tf, p.dx, p.dy));
      final boost = focusBoost * lay.scale;
      final lift = c.type == CreatureType.bird ? v.s * 0.12 * lay.scale : 0.0;
      final center = ground - Offset(0, SpeciesRenderer.centerLift(c) * boost * v.s + lift);
      out.add((c, center, SpeciesRenderer.radius(c) * boost * v.s));
    }
    return out;
  }

  /// 種ごとの立体モデルと、名前ラベル（適合度が低いと赤みがかる）
  void _speciesObject(Creature c, Offset ground, Habitat h, double scale) {
    final fit = notifier.suitability(c, h, s: state).clamp(0.0, 1.0);
    final pop = state.population[c.id] ?? 0;
    final boost = focusBoost * scale;
    final lift = c.type == CreatureType.bird ? _v.s * 0.12 * scale : 0.0;
    if (c.type == CreatureType.bird) _shadow(ground, 0.04 * scale);
    if (c.endangered) _rareAura(ground, SpeciesRenderer.centerLift(c) * boost * _v.s + lift);
    SpeciesRenderer.paint(_c, c, ground - Offset(0, lift), _v.s, t, fit: fit, pop: pop, boost: boost);

    final label = Color.lerp(const Color(0xFFE08A6A), Colors.white, fit)!;
    final tp = TextPainter(
      text: TextSpan(
        text: (c.endangered ? '★ ' : '') + c.nameJa,
        style: TextStyle(
            fontSize: 9, color: c.endangered ? _gold : label, shadows: const [Shadow(blurRadius: 3, color: Colors.black)]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(_c, ground + Offset(-tp.width / 2, 4));
  }

  /// 森・山の斜面と、川の土手・浜・池のほとりに生える木（植物のモデルと重ならない場所に）
  void _addTrees(List<_Item> items, Habitat h) {
    final lay = layoutStage(h, habitatSpecies(h, state, notifier, creatures));
    final taken = lay.pos.values.toList();
    bool free(double x, double y) => taken.every((q) => (q - Offset(x, y)).distance > 0.1);

    void plant(double x, double y, bool conifer, double size, int seed, {double limit = 0.6}) {
      if (_waterZ(x, y) != null || !free(x, y)) return;
      final hh = _tf.heightAt(x, y);
      if (hh > limit) return;
      items.add(_Item(_v.depth(x, y), () => _miniTree(_v.p(x, y, hh), size * _v.s, conifer, seed)));
    }

    final rng = Random(h.index * 211 + 9);
    switch (h) {
      case Habitat.forest:
      case Habitat.mountainLow:
      case Habitat.mountainMid:
      case Habitat.mountainHigh:
        final r = _stageRects[h]!;
        final n = switch (h) {
          Habitat.forest => 30,
          Habitat.mountainLow => 32,
          Habitat.mountainMid => 42,
          _ => 12,
        };
        final limit = h == Habitat.mountainHigh ? 0.6 : 0.47;
        for (var k = 0; k < n; k++) {
          final x = r.left + rng.nextDouble() * r.width, y = r.top + rng.nextDouble() * r.height;
          final conifer = h == Habitat.forest ? rng.nextDouble() < 0.35 : (h == Habitat.mountainLow ? rng.nextDouble() < 0.55 : true);
          final size = (0.07 + rng.nextDouble() * 0.045) * (h == Habitat.mountainHigh ? 0.8 : 1.0);
          if (_inRiver(x, y, 2.3) || _inPond(x, y, 1.35)) continue;
          plant(x, y, conifer, size, h.index * 100 + k, limit: limit);
        }
      case Habitat.river:
        // 川の土手：柳のような広葉樹
        for (var k = 0; k < 18; k++) {
          final y = -0.62 + rng.nextDouble() * 1.4;
          final side = rng.nextBool() ? 1.0 : -1.0;
          final x = riverX(y) + side * (riverHalf(y) + 0.1 + rng.nextDouble() * 0.14);
          plant(x, y, false, 0.075 + rng.nextDouble() * 0.04, 700 + k);
        }
      case Habitat.ocean:
        // 海岸：クロマツのような針葉樹
        for (var k = 0; k < 14; k++) {
          final x = -1.45 + rng.nextDouble() * 2.9;
          plant(x, shoreY(x) - 0.1 - rng.nextDouble() * 0.12, true, 0.07 + rng.nextDouble() * 0.04, 800 + k);
        }
      case Habitat.pond:
        // 池のほとり
        for (var k = 0; k < 10; k++) {
          final a = rng.nextDouble() * 2 * pi, f = 1.12 + rng.nextDouble() * 0.3;
          final x = _pondC.dx + cos(a) * _pondRx * f, y = _pondC.dy + sin(a) * _pondRy * f;
          if (y < -0.3 && (x - _pondC.dx).abs() < 0.36) continue;
          plant(x, y, false, 0.07 + rng.nextDouble() * 0.035, 900 + k);
        }
    }
  }

  void _stageItems(List<_Item> items, Habitat h) {
    _addObstacles(items, h, state.areas[h]!.obstacles);
    _addStageCreatures(items, h);
    _addScenery(items, h);
    _addTrees(items, h);
  }

  void _miniTree(Offset b, double sz, bool conifer, int seed) {
    _c.drawOval(Rect.fromCenter(center: b, width: sz * 0.7, height: sz * 0.28), Paint()..color = Colors.black.withValues(alpha: 0.25));
    final rng = Random(seed);
    if (conifer) {
      final base = Color.lerp(const Color(0xFF244A2C), const Color(0xFF3F7A44), rng.nextDouble())!;
      for (var i = 0; i < 3; i++) {
        final y0 = b.dy - sz * 0.18 * i;
        final hw = sz * 0.2 * (1 - i * 0.25);
        final tri = Path()
          ..moveTo(b.dx - hw, y0)
          ..lineTo(b.dx, y0 - sz * 0.42)
          ..lineTo(b.dx + hw, y0)
          ..close();
        _c.drawPath(tri, Paint()..color = _shade(base, 0.75 + i * 0.12));
        _c.drawLine(Offset(b.dx, y0 - sz * 0.42), Offset(b.dx - hw, y0), Paint()..color = Colors.white.withValues(alpha: 0.1)..strokeWidth = 1);
      }
    } else {
      final base = Color.lerp(const Color(0xFF3F7A34), const Color(0xFF8DB04A), rng.nextDouble())!;
      _c.drawRect(Rect.fromLTRB(b.dx - 1, b.dy - sz * 0.25, b.dx + 1, b.dy), Paint()..color = const Color(0xFF4A3826));
      final c = b - Offset(0, sz * 0.4);
      _c.drawCircle(
          c,
          sz * 0.28,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.4, -0.5),
              colors: [Color.lerp(base, Colors.white, 0.25)!, _shade(base, 0.55)],
            ).createShader(Rect.fromCircle(center: c, radius: sz * 0.28)));
    }
  }

  void _addObstacles(List<_Item> items, Habitat h, int count) {
    final rng = Random(h.index * 97 + 13);
    for (var i = 0; i < count; i++) {
      final p = stagePoint(h, 0.1 + rng.nextDouble() * 0.8, 0.1 + rng.nextDouble() * 0.8);
      final x = p.dx, y = p.dy;
      final z = surfaceZ(_tf, x, y);
      final isLog = (i + h.index) % 2 == 0;
      final alongX = rng.nextBool();
      final seed = h.index * 31 + i;
      items.add(_Item(_v.depth(x, y), () {
        if (isLog) {
          final lx = alongX ? 0.09 : 0.022, ly = alongX ? 0.022 : 0.09;
          _shadow(_v.p(x, y, z), 0.1);
          _box(x - lx, y - ly, x + lx, y + ly, z, z + 0.04, const Color(0xFF7A5C3A), const Color(0xFF5A4630));
          final m = _v.p(x, y, z + 0.04);
          _c.drawOval(Rect.fromCenter(center: m, width: _v.s * 0.1, height: _v.s * 0.03),
              Paint()..color = const Color(0xFF5E8F34).withValues(alpha: 0.9));
          _c.drawCircle(m + Offset(alongX ? _v.s * 0.07 : 0, 0), 1.6, Paint()..color = const Color(0xFFB8946A));
        } else {
          _rock(x, y, z, 0.07 + (seed % 3) * 0.012, seed);
        }
      }));
    }
  }

  void _label(Habitat h) {
    final r = _stageRects[h]!;
    final c = r.center;
    final a = state.areas[h]!;
    final o = _v.p(c.dx, c.dy, surfaceZ(_tf, c.dx, c.dy) + (h.isMountain ? 0.28 : 0.1));
    final tp = TextPainter(
      text: TextSpan(
        text: h.label + (a.protectedArea ? '（保護区）' : ''),
        style: const TextStyle(fontSize: 12, color: Colors.white, shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(_c, o - Offset(tp.width / 2, tp.height / 2));
  }

  /// ステージ以外を暗くして、地形の一部分としてステージを浮かび上がらせる
  void _dim(Habitat h) {
    final c = _stageRects[h]!.center;
    final region = _v.stagePath(h, surfaceZ(_tf, c.dx, c.dy) + 0.02);
    final full = Path()..addRect(Offset.zero & _size);
    _c.drawPath(Path.combine(PathOperation.difference, full, region), Paint()..color = Colors.black.withValues(alpha: 0.5));
    _c.drawPath(
        region,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _gold.withValues(alpha: 0.55));
  }

  // ---- 風景 ---------------------------------------------------------------

  /// 自然な小物だけを、まばらに置く（地形の一部として、世界座標で配置）
  void _addScenery(List<_Item> items, Habitat h) {
    final tf = _tf;
    final rng = Random(h.index * 131 + 7);

    void add(double x, double y, void Function(double x, double y, double z) draw) {
      final z = surfaceZ(tf, x, y);
      items.add(_Item(_v.depth(x, y), () => draw(x, y, z)));
    }

    switch (h) {
      case Habitat.forest:
        add(-1.2, 0.0, (x, y, z) => _rock(x, y, z, 0.1, 1));
        add(-0.78, 0.3, (x, y, z) => _rock(x, y, z, 0.085, 2));
        add(-1.35, -0.4, (x, y, z) => _rock(x, y, z, 0.06, 3));
        add(-1.3, 0.25, (x, y, z) => _flowerCluster(x, y, z, 0, 5, 11));
        add(-0.9, -0.3, (x, y, z) => _flowerCluster(x, y, z, 1, 5, 12));
        add(-0.7, 0.05, (x, y, z) => _flowerCluster(x, y, z, 2, 4, 13));
        add(-1.05, 0.4, (x, y, z) => _flowerCluster(x, y, z, 3, 3, 14));
        for (var i = 0; i < 6; i++) {
          final x = -1.5 + rng.nextDouble() * 0.95, y = -0.55 + rng.nextDouble() * 1.0;
          final rot = rng.nextDouble() * pi;
          add(x, y, (x, y, z) => _petal(x, y, z, rot));
        }
      case Habitat.pond:
        // 里の池のほとりの和風の家（家の前が池）
        add(1.12, -0.5, (x, y, z) => _wafuHouse(x, y, z));
        add(0.8, 0.05, (x, y, z) => _rock(x, y, z, 0.085, 4));
        add(1.45, 0.22, (x, y, z) => _rock(x, y, z, 0.07, 5));
        add(0.85, 0.32, (x, y, z) => _reeds(x, y, z, 0.8));
        add(1.42, -0.15, (x, y, z) => _reeds(x, y, z, 0.8));
        add(1.2, 0.4, (x, y, z) => _reeds(x, y, z, 0.8));
        add(1.47, 0.4, (x, y, z) => _flowerCluster(x, y, z, 2, 4, 15));
      case Habitat.river:
        for (var i = 0; i < 4; i++) {
          final y = -0.55 + i * 0.4;
          add(riverX(y) + riverHalf(y) + 0.07, y, (x, y, z) => _rock(x, y, z, 0.06, 6 + i));
          add(riverX(y + 0.1) - riverHalf(y + 0.1) - 0.07, y + 0.1, (x, y, z) => _rock(x, y, z, 0.055, 16 + i));
        }
        add(riverX(0.7) + riverHalf(0.7) + 0.05, 0.7, (x, y, z) => _reeds(x, y, z, 0.8));
        add(0.34, -0.55, (x, y, z) => _flowerCluster(x, y, z, 0, 4, 16));
      case Habitat.ocean:
        const corals = [Color(0xFFE86A8A), Color(0xFFF08A4A), Color(0xFFB07AE0), Color(0xFFF2B84A)];
        const cx = [-1.05, -0.45, 0.55, 1.1, 0.1];
        for (var i = 0; i < cx.length; i++) {
          final x = cx[i], y = shoreY(x) + 0.2 + (i % 3) * 0.12;
          add(x, y, (x, y, z) => _coral(x, y, z - 0.01, corals[i % 4]));
        }
        for (var i = 0; i < 6; i++) {
          final x = -1.3 + i * 0.5, y = shoreY(x) - 0.03;
          add(x, y, (x, y, z) => i.isEven ? _shell(x, y, z) : _starfish(x, y, z));
        }
        add(1.3, 1.25, (x, y, z) => _rock(x, y, z, 0.09, 20));
        add(-1.35, 1.2, (x, y, z) => _rock(x, y, z, 0.075, 21));
      case Habitat.mountainLow:
        add(-1.1, -1.0, (x, y, z) => _rock(x, y, z, 0.09, 30));
        add(-0.8, -1.2, (x, y, z) => _rock(x, y, z, 0.07, 31));
        add(-1.3, -0.95, (x, y, z) => _flowerCluster(x, y, z, 2, 3, 33));
      case Habitat.mountainMid:
        add(-0.1, -1.05, (x, y, z) => _rock(x, y, z, 0.1, 32));
        add(0.2, -1.25, (x, y, z) => _rock(x, y, z, 0.08, 34));
        add(-0.3, -0.95, (x, y, z) => _flowerCluster(x, y, z, 2, 3, 35));
      case Habitat.mountainHigh:
        add(0.7, -1.0, (x, y, z) => _rock(x, y, z, 0.1, 36));
        add(1.1, -1.2, (x, y, z) => _rock(x, y, z, 0.09, 37));
        add(0.55, -0.95, (x, y, z) => _flowerCluster(x, y, z, 0, 3, 38));
    }
  }


  // ---- 基本図形 ----------------------------------------------------------

  Color _shade(Color c, double k) => Color.lerp(Colors.black, c, k.clamp(0.0, 1.0))!;

  /// 直方体。見えている側面だけを、向きに応じた明るさで描く。
  void _box(double x0, double y0, double x1, double y1, double z0, double z1,
      Color top, Color side,
      {Color? edge}) {
    final v = _v;
    final faces = [
      (x0, y0, x1, y0, 0.0, -1.0),
      (x1, y0, x1, y1, 1.0, 0.0),
      (x1, y1, x0, y1, 0.0, 1.0),
      (x0, y1, x0, y0, -1.0, 0.0),
    ];
    for (final f in faces) {
      final nx = f.$5 * v.ca - f.$6 * v.sa;
      final ny = f.$5 * v.sa + f.$6 * v.ca;
      if (nx + ny <= 0.0001) continue; // 裏側
      final k = 0.62 - 0.22 * (nx - ny) / 1.414;
      final path = Path()
        ..moveTo(v.p(f.$1, f.$2, z1).dx, v.p(f.$1, f.$2, z1).dy)
        ..lineTo(v.p(f.$3, f.$4, z1).dx, v.p(f.$3, f.$4, z1).dy)
        ..lineTo(v.p(f.$3, f.$4, z0).dx, v.p(f.$3, f.$4, z0).dy)
        ..lineTo(v.p(f.$1, f.$2, z0).dx, v.p(f.$1, f.$2, z0).dy)
        ..close();
      _c.drawPath(path, Paint()..color = _shade(side, k));
    }
    final topPath = Path()
      ..moveTo(v.p(x0, y0, z1).dx, v.p(x0, y0, z1).dy)
      ..lineTo(v.p(x1, y0, z1).dx, v.p(x1, y0, z1).dy)
      ..lineTo(v.p(x1, y1, z1).dx, v.p(x1, y1, z1).dy)
      ..lineTo(v.p(x0, y1, z1).dx, v.p(x0, y1, z1).dy)
      ..close();
    _c.drawPath(topPath, Paint()..color = top);
    if (edge != null) {
      _c.drawPath(
          topPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = edge);
    }
  }

  void _bokeh(Size size) {
    final rng = Random(7);
    for (var i = 0; i < 9; i++) {
      final c = Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height);
      final r = 18 + rng.nextDouble() * 38;
      final col = [const Color(0xFFE8B96A), const Color(0xFF7FD6D0), const Color(0xFFB5733A)][i % 3];
      _c.drawCircle(
          c,
          r,
          Paint()
            ..color = col.withValues(alpha: 0.05 + 0.04 * sin(t * 0.3 + i))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    }
  }

  // ---- 石積みの鉢 ---------------------------------------------------------

  // ---- タイル ------------------------------------------------------------

  Color _tintLight(Color c) => Color.lerp(c, const Color(0xFFD8F080), 0.4)!;

  // ---- 山 -----------------------------------------------------------------

  // ---- 池のほとりの和風の家 -------------------------------------------------

  void _quad(List<Offset> pts, Color c, {Color? edge}) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final o in pts.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    path.close();
    _c.drawPath(path, Paint()..color = c);
    if (edge != null) {
      _c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = edge);
    }
  }

  /// 壁面に障子を描く（face: 'S' は y 一定の面、'E' は x 一定の面）
  void _shoji(String face, double fixed, double a0, double a1, double z0, double z1) {
    final pts = face == 'S'
        ? [_v.p(a0, fixed, z0), _v.p(a1, fixed, z0), _v.p(a1, fixed, z1), _v.p(a0, fixed, z1)]
        : [_v.p(fixed, a0, z0), _v.p(fixed, a1, z0), _v.p(fixed, a1, z1), _v.p(fixed, a0, z1)];
    final glow = 0.85 + 0.08 * sin(t * 1.7 + a0 * 9);
    _quad(pts, Color.lerp(const Color(0xFFF2E2B0), const Color(0xFFFFEFC0), glow - 0.8)!, edge: const Color(0xFF3A2A1E));
    // 組子（格子）
    for (var k = 1; k < 3; k++) {
      _c.drawLine(Offset.lerp(pts[0], pts[1], k / 3)!, Offset.lerp(pts[3], pts[2], k / 3)!,
          Paint()
            ..color = const Color(0xFF5A4630)
            ..strokeWidth = 0.9);
    }
    for (var k = 1; k < 3; k++) {
      _c.drawLine(Offset.lerp(pts[0], pts[3], k / 3)!, Offset.lerp(pts[1], pts[2], k / 3)!,
          Paint()
            ..color = const Color(0xFF5A4630)
            ..strokeWidth = 0.9);
    }
    final c = Offset.lerp(Offset.lerp(pts[0], pts[1], 0.5)!, Offset.lerp(pts[3], pts[2], 0.5)!, 0.5)!;
    _glow(c, _v.s * 0.1, a: 0.35);
  }

  /// 池に面した和風の家：白い漆喰の壁、黒い柱、障子、縁側、瓦屋根（寄棟）
  void _wafuHouse(double cx, double cy, double z) {
    const w = 0.19, d = 0.11, wallH = 0.085;
    final x0 = cx - w, x1 = cx + w, y0 = cy - d, y1 = cy + d;

    // 苔むした岸（家の土台になる陸地。前は池）
    _box(cx - 0.3, cy - 0.16, cx + 0.3, cy + 0.2, z, z + 0.03, const Color(0xFF55803A), const Color(0xFF6E6A5E));
    final rng = Random(5);
    for (var k = 0; k < 26; k++) {
      final o = _v.p(cx - 0.28 + rng.nextDouble() * 0.56, cy - 0.14 + rng.nextDouble() * 0.32, z + 0.03);
      _c.drawOval(Rect.fromCenter(center: o, width: 4 + rng.nextDouble() * 6, height: 2.2),
          Paint()..color = Color.lerp(const Color(0xFF3F7A34), const Color(0xFF9CC050), rng.nextDouble())!.withValues(alpha: 0.7));
    }
    final g = z + 0.03;
    _shadow(_v.p(cx, cy, g), 0.34);

    // 石の基礎と壁
    const stone = Color(0xFF8A877F);
    _box(x0 - 0.012, y0 - 0.012, x1 + 0.012, y1 + 0.012, g, g + 0.02, stone, const Color(0xFF5E5C56));
    final zb = g + 0.02;
    _box(x0, y0, x1, y1, zb, zb + wallH, const Color(0xFFF1EBDD), const Color(0xFFE2DAC4));

    // 黒い柱（四隅と前面の中間）と、長押（水平の梁）
    const wood = Color(0xFF3A2A1E), woodSide = Color(0xFF2A1E14);
    for (final px in [x0, x0 + (x1 - x0) / 3, x0 + (x1 - x0) * 2 / 3, x1]) {
      _box(px - 0.006, y1 - 0.004, px + 0.006, y1 + 0.008, zb, zb + wallH, wood, woodSide);
    }
    for (final py in [y0, y1]) {
      _box(x0 - 0.006, py - 0.006, x0 + 0.006, py + 0.006, zb, zb + wallH, wood, woodSide);
      _box(x1 - 0.006, py - 0.006, x1 + 0.006, py + 0.006, zb, zb + wallH, wood, woodSide);
    }
    _box(x0, y1 - 0.003, x1, y1 + 0.007, zb + wallH - 0.012, zb + wallH, wood, woodSide);

    // 障子（南面・東面）
    if (_faceVisible(0, 1)) {
      final seg = (x1 - x0) / 3;
      for (var k = 0; k < 3; k++) {
        _shoji('S', y1 + 0.001, x0 + seg * k + 0.008, x0 + seg * (k + 1) - 0.008, zb + 0.008, zb + wallH - 0.016);
      }
    }
    if (_faceVisible(1, 0)) {
      _shoji('E', x1 + 0.001, cy - 0.05, cy + 0.05, zb + 0.008, zb + wallH - 0.016);
    }

    // 縁側（板張りのデッキ）と沓脱石
    const deck = Color(0xFFA98B62), deckSide = Color(0xFF6A5236);
    _box(x0 - 0.02, y1, x1 + 0.02, y1 + 0.06, zb - 0.004, zb + 0.008, deck, deckSide);
    for (var k = 1; k < 8; k++) {
      final xx = x0 - 0.02 + (x1 - x0 + 0.04) * k / 8;
      _c.drawLine(_v.p(xx, y1, zb + 0.008), _v.p(xx, y1 + 0.06, zb + 0.008),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.18)
            ..strokeWidth = 0.8);
    }
    _box(cx - 0.04, y1 + 0.075, cx + 0.04, y1 + 0.115, g, g + 0.012, const Color(0xFFA9A8A0), const Color(0xFF6E6D67));

    // 瓦屋根（寄棟）
    final ez = zb + wallH + 0.006;
    final ex0 = x0 - 0.05, ex1 = x1 + 0.05, ey0 = y0 - 0.05, ey1 = y1 + 0.075;
    final rz = ez + 0.08;
    final rx0 = x0 + 0.04, rx1 = x1 - 0.04;
    Offset pp(double x, double y, double zz) => _v.p(x, y, zz);
    final roofFaces = [
      // (法線, 頂点列)
      ((0.0, 1.0), [pp(ex0, ey1, ez), pp(ex1, ey1, ez), pp(rx1, cy, rz), pp(rx0, cy, rz)]),
      ((0.0, -1.0), [pp(ex0, ey0, ez), pp(ex1, ey0, ez), pp(rx1, cy, rz), pp(rx0, cy, rz)]),
      ((1.0, 0.0), [pp(ex1, ey0, ez), pp(ex1, ey1, ez), pp(rx1, cy, rz)]),
      ((-1.0, 0.0), [pp(ex0, ey0, ez), pp(ex0, ey1, ez), pp(rx0, cy, rz)]),
    ];
    const kawara = Color(0xFF454B54);
    for (final rf in roofFaces) {
      final nx = rf.$1.$1 * _v.ca - rf.$1.$2 * _v.sa;
      final ny = rf.$1.$1 * _v.sa + rf.$1.$2 * _v.ca;
      if (nx + ny <= 0.0001) continue;
      final k = 0.66 - 0.24 * (nx - ny) / 1.414;
      _quad(rf.$2, _shade(kawara, k), edge: Colors.black.withValues(alpha: 0.45));
      // 瓦の筋
      final pts = rf.$2;
      if (pts.length == 4) {
        for (var j = 1; j < 6; j++) {
          _c.drawLine(Offset.lerp(pts[0], pts[3], j / 6)!, Offset.lerp(pts[1], pts[2], j / 6)!,
              Paint()
                ..color = Colors.black.withValues(alpha: 0.28)
                ..strokeWidth = 0.9);
        }
      } else {
        for (var j = 1; j < 4; j++) {
          _c.drawLine(Offset.lerp(pts[0], pts[2], j / 4)!, Offset.lerp(pts[1], pts[2], j / 4)!,
              Paint()
                ..color = Colors.black.withValues(alpha: 0.28)
                ..strokeWidth = 0.9);
        }
      }
    }
    // 棟の鬼瓦
    for (final rx in [rx0, rx1]) {
      _box(rx - 0.012, cy - 0.012, rx + 0.012, cy + 0.012, rz, rz + 0.016, const Color(0xFF2E3238), const Color(0xFF1E2126));
    }
  }

  // ---- 立体物 ------------------------------------------------------------

  /// 苔むした岩：不規則な形に陰影をつけ、上面に苔をのせる
  void _rock(double x, double y, double z, double size, int seed) {
    final b = _v.p(x, y, z);
    final s = _v.s * size;
    final rng = Random(seed * 13 + 5);
    _shadow(b, size * 1.1);
    const n = 10;
    final pts = <Offset>[];
    for (var k = 0; k < n; k++) {
      final a = k * 2 * pi / n;
      final r = s * (0.75 + rng.nextDouble() * 0.4);
      pts.add(Offset(b.dx + cos(a) * r * 1.2, b.dy - s * 0.5 + sin(a) * r * 0.75));
    }
    final path = Path();
    for (var k = 0; k < n; k++) {
      final p0 = pts[k], p1 = pts[(k + 1) % n];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      if (k == 0) path.moveTo(mid.dx, mid.dy);
      path.quadraticBezierTo(p1.dx, p1.dy, (p1.dx + pts[(k + 2) % n].dx) / 2, (p1.dy + pts[(k + 2) % n].dy) / 2);
    }
    path.close();
    final bounds = path.getBounds();
    _c.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.6),
            radius: 1.0,
            colors: const [Color(0xFFB9B2A4), Color(0xFF8C8578), Color(0xFF55514A)],
            stops: const [0, 0.55, 1],
          ).createShader(bounds));
    _c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.black.withValues(alpha: 0.35));
    // ひび割れ
    for (var k = 0; k < 3; k++) {
      final a = bounds.center + Offset((rng.nextDouble() - 0.5) * s, (rng.nextDouble() - 0.5) * s * 0.5);
      _c.drawLine(a, a + Offset((rng.nextDouble() - 0.5) * s * 0.6, rng.nextDouble() * s * 0.3),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.3)
            ..strokeWidth = 0.7);
    }
    // 上面の苔（明暗2色の房）
    for (var k = 0; k < 7; k++) {
      final o = Offset(bounds.center.dx + (rng.nextDouble() - 0.5) * s * 1.3, bounds.top + s * (0.12 + rng.nextDouble() * 0.35));
      final col = Color.lerp(const Color(0xFF3F7A2E), const Color(0xFF9CC050), rng.nextDouble())!;
      _c.drawOval(Rect.fromCenter(center: o, width: s * (0.3 + rng.nextDouble() * 0.3), height: s * 0.22), Paint()..color = col.withValues(alpha: 0.95));
    }
  }

  void _shadow(Offset base, double size) {
    _c.drawOval(Rect.fromCenter(center: base, width: size * _v.s * 2, height: size * _v.s),
        Paint()..color = Colors.black.withValues(alpha: 0.28));
  }

  // ---- 拡大表示：写真を立て看板のように置く -------------------------------

  /// 動物がいま姿を見せているか（0〜1、0=不在）。
  /// 環境に合うことと、その場に居ることは別なので、珍しい種ほどまれにしか現れない。
  /// 約20秒ごとに抽選し直し、出入りは短くフェードする。植物は動かないので常に 1。
  static double presenceAlpha(Creature c, double t, int turn, int pop) {
    if (c.type == CreatureType.plant) return 1;
    const base = [0.0, 0.9, 0.7, 0.45, 0.25, 0.12]; // rarity 1〜5
    final red = c.redList == 'CR' ? 0.4 : c.redList == 'EN' ? 0.55 : c.redList == 'VU' ? 0.7 : 1.0;
    final chance = base[c.rarity.clamp(1, 5)] * red * (0.6 + 0.4 * min(pop, 60) / 60);
    const window = 20.0;
    final idx = (t / window).floor() + turn * 7;
    final r = Random(c.id.hashCode ^ (idx * 7919)).nextDouble();
    if (r > chance) return 0;
    final f = (t % window) / window;
    return (min(f, 1 - f) / 0.08).clamp(0.0, 1.0);
  }

  /// 指定の透明度で描く（フェード用）
  void _withOpacity(double a, Offset center, void Function() draw) {
    if (a >= 0.99) {
      draw();
      return;
    }
    _c.saveLayer(Rect.fromCenter(center: center, width: _v.s * 1.6, height: _v.s * 1.6),
        Paint()..color = Colors.white.withValues(alpha: a));
    draw();
    _c.restore();
  }

  /// 拡大表示では、モデルを大きく描いて特徴が見えるようにする
  static const double focusBoost = 1.2;

  /// 1エリアに一度に出す数の上限（種類ごと）。種が多くても画面がごちゃつかないように
  static const Map<CreatureType, int> _showLimit = {
    CreatureType.plant: 5,
    CreatureType.bird: 3,
    CreatureType.fish: 3,
    CreatureType.animal: 3,
  };

  /// このエリアに生息している（個体数>0）種のうち、いまの環境に最も適するものを種類ごとに上限まで
  static List<Creature> habitatSpecies(Habitat h, ConservationState state,
      ConservationNotifier notifier, List<Creature> creatures) {
    final scored = <(Creature, double)>[
      for (final c in creatures)
        if (notifier.lives(c, h, s: state)) (c, notifier.suitability(c, h, s: state)),
    ];
    // 適合度が高い順。同点は id で固定して、再描画のたびに入れ替わらないようにする
    scored.sort((a, b) {
      final d = b.$2.compareTo(a.$2);
      return d != 0 ? d : a.$1.id.compareTo(b.$1.id);
    });
    final count = <CreatureType, int>{};
    final out = <Creature>[];
    for (final (c, _) in scored) {
      final n = count[c.type] ?? 0;
      if (n >= (_showLimit[c.type] ?? 3)) continue;
      count[c.type] = n + 1;
      out.add(c);
    }
    return out;
  }

  /// 絶滅危惧種のしるし：金色のオーラと、またたく星
  void _rareAura(Offset ground, double lift) {
    final center = ground - Offset(0, lift);
    final r = _v.s * 0.2;
    _c.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            _gold.withValues(alpha: 0.38 + 0.12 * sin(t * 3)),
            Colors.transparent,
          ]).createShader(Rect.fromCircle(center: center, radius: r)));
    for (var k = 0; k < 4; k++) {
      final a = t * 0.9 + k * pi / 2;
      final o = center + Offset(cos(a) * r * 0.75, sin(a) * r * 0.55 - r * 0.2);
      final tw = (0.4 + 0.6 * sin(t * 4 + k * 1.7)).clamp(0.0, 1.0);
      final sz = 2.5 + 2.5 * tw;
      _c.drawLine(o - Offset(sz, 0), o + Offset(sz, 0), Paint()..color = Colors.white.withValues(alpha: tw)..strokeWidth = 1);
      _c.drawLine(o - Offset(0, sz), o + Offset(0, sz), Paint()..color = Colors.white.withValues(alpha: tw)..strokeWidth = 1);
    }
  }

  // ---- 風景（箱庭らしい小物） --------------------------------------------

  Paint _fill(Color c) => Paint()..color = c;

  void _glow(Offset c, double radius,
      {double a = 0.6, Color color = const Color(0xFFFFD27A)}) {
    _c.drawCircle(
        c,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [color.withValues(alpha: a), Colors.transparent])
              .createShader(Rect.fromCircle(center: c, radius: radius)));
  }

  bool _faceVisible(double nx, double ny) {
    final x = nx * _v.ca - ny * _v.sa;
    final y = nx * _v.sa + ny * _v.ca;
    return x + y > 0.001;
  }

  Path _poly(List<Offset> pts) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final o in pts.skip(1)) {
      p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  void _flower(double x, double y, double z, Color petal, double sc) {
    final b = _v.p(x, y, z);
    final s = _v.s * sc * 0.42;
    _c.drawLine(b, b - Offset(0, s * 0.22),
        Paint()
          ..color = const Color(0xFF3F7A34)
          ..strokeWidth = 1.2);
    final c = b - Offset(0, s * 0.25) + Offset(sin(t + x * 20) * 0.6, 0);
    for (var k = 0; k < 5; k++) {
      final a = k * 2 * pi / 5 + x * 10;
      _c.drawCircle(c + Offset(cos(a), sin(a) * 0.8) * s * 0.06, s * 0.055, _fill(petal));
    }
    _c.drawCircle(c, s * 0.04, _fill(const Color(0xFFFFD24A)));
  }

  void _bush(double x, double y, double z, double sc, Color col) {
    final b = _v.p(x, y, z);
    final r = _v.s * sc;
    _shadow(b, sc * 0.5);
    for (final o in [const Offset(-0.5, -0.35), const Offset(0.5, -0.3), const Offset(0, -0.7)]) {
      final c = b + o * r;
      _c.drawCircle(
          c,
          r * 0.55,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.4, -0.5),
              colors: [Color.lerp(col, Colors.white, 0.3)!, _shade(col, 0.5)],
            ).createShader(Rect.fromCircle(center: c, radius: r * 0.55)));
    }
  }

  void _reeds(double x, double y, double z, double sc) {
    final b = _v.p(x, y, z);
    final s = _v.s * sc * 0.6;
    for (var k = -2; k <= 2; k++) {
      final sway = sin(t * 1.2 + k + x * 7) * 2;
      final tip = b + Offset(k * 3.0 + sway, -s * (0.55 - k.abs() * 0.07));
      _c.drawLine(b + Offset(k * 1.5, 0), tip,
          Paint()
            ..color = const Color(0xFF6E9A4A)
            ..strokeWidth = 1.4);
      if (k.abs() != 1) {
        _c.drawLine(tip, tip - Offset(0, s * 0.1),
            Paint()
              ..color = const Color(0xFF6A4A2A)
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round);
      }
    }
  }

  void _coral(double x, double y, double z, Color col) {
    final b = _v.p(x, y, z);
    final s = _v.s;
    final p = Paint()
      ..color = col.withValues(alpha: 0.9)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var k = -2; k <= 2; k++) {
      final tip = b + Offset(k * s * 0.03, -s * (0.1 + (2 - k.abs()) * 0.03));
      _c.drawLine(b, tip, p);
      _c.drawCircle(tip, 2.6, _fill(col));
      if (k.abs() < 2) _c.drawLine(tip, tip + Offset(k * 2.5, -s * 0.03), p);
    }
  }

  void _shell(double x, double y, double z) {
    final b = _v.p(x, y, z);
    _c.drawOval(Rect.fromCenter(center: b, width: 7, height: 4.5), _fill(const Color(0xFFF1E3CE)));
    _c.drawLine(b - const Offset(2, 0), b + const Offset(2, 0),
        Paint()..color = const Color(0xFFC9AE8A));
  }

  void _starfish(double x, double y, double z) {
    final b = _v.p(x, y, z);
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final r = k.isEven ? 5.5 : 2.4;
      final a = -pi / 2 + k * pi / 5;
      final o = b + Offset(cos(a) * r, sin(a) * r * 0.7);
      k == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    _c.drawPath(path..close(), _fill(const Color(0xFFE8895A)));
  }

  // ---- 花の群れ（スミレ・プリムラ・ヒナギク・スズラン） --------------------

  void _violet(double x, double y, double z, double sc) {
    final b = _v.p(x, y, z);
    final u = _v.s * sc;
    for (final d in [-1.0, 1.0]) {
      _c.drawOval(Rect.fromCenter(center: b + Offset(d * u * 0.05, -u * 0.015), width: u * 0.08, height: u * 0.05),
          Paint()..color = const Color(0xFF3F7A34));
    }
    _c.drawLine(b, b - Offset(0, u * 0.1), Paint()..color = const Color(0xFF5E8F3A)..strokeWidth = 1);
    final c = b - Offset(0, u * 0.11);
    const petal = Color(0xFF8E62C8);
    for (var k = 0; k < 5; k++) {
      final a = -pi / 2 + (k - 2) * 0.55 + (k == 2 ? 0 : 0);
      final big = k == 1 || k == 3;
      _c.drawOval(Rect.fromCenter(center: c + Offset(cos(a) * u * 0.035, sin(a) * u * 0.03), width: u * (big ? 0.06 : 0.05), height: u * 0.05),
          Paint()..color = k == 2 ? const Color(0xFFB08ADC) : petal);
    }
    _c.drawCircle(c, u * 0.012, Paint()..color = const Color(0xFFF4E48A));
  }

  void _primrose(double x, double y, double z, double sc) {
    final b = _v.p(x, y, z);
    final u = _v.s * sc;
    _c.drawOval(Rect.fromCenter(center: b + Offset(0, -u * 0.01), width: u * 0.12, height: u * 0.05), Paint()..color = const Color(0xFF4F8A3A));
    _c.drawLine(b, b - Offset(0, u * 0.09), Paint()..color = const Color(0xFF6E9A4A)..strokeWidth = 1);
    final c = b - Offset(0, u * 0.1);
    for (var k = 0; k < 5; k++) {
      final a = k * 2 * pi / 5 - pi / 2;
      _c.drawCircle(c + Offset(cos(a), sin(a) * 0.85) * u * 0.03, u * 0.027, Paint()..color = const Color(0xFFF6D44A));
    }
    _c.drawCircle(c, u * 0.014, Paint()..color = const Color(0xFFE8A02A));
  }

  void _daisy(double x, double y, double z, double sc) {
    final b = _v.p(x, y, z);
    final u = _v.s * sc;
    _c.drawOval(Rect.fromCenter(center: b + Offset(0, -u * 0.01), width: u * 0.1, height: u * 0.045), Paint()..color = const Color(0xFF4F8A3A));
    _c.drawLine(b, b - Offset(0, u * 0.13), Paint()..color = const Color(0xFF6E9A4A)..strokeWidth = 1);
    final c = b - Offset(0, u * 0.14);
    for (var k = 0; k < 14; k++) {
      final a = k * 2 * pi / 14;
      _c.drawLine(c, c + Offset(cos(a), sin(a) * 0.8) * u * 0.05,
          Paint()
            ..color = Colors.white
            ..strokeWidth = u * 0.016
            ..strokeCap = StrokeCap.round);
    }
    _c.drawCircle(c, u * 0.02, Paint()..color = const Color(0xFFF2B21A));
  }

  void _lilyValley(double x, double y, double z, double sc) {
    final b = _v.p(x, y, z);
    final u = _v.s * sc;
    for (final d in [-1.0, 1.0]) {
      _c.drawPath(
          Path()
            ..moveTo(b.dx, b.dy)
            ..quadraticBezierTo(b.dx + d * u * 0.06, b.dy - u * 0.12, b.dx + d * u * 0.11, b.dy - u * 0.04)
            ..quadraticBezierTo(b.dx + d * u * 0.05, b.dy - u * 0.07, b.dx, b.dy),
          Paint()..color = const Color(0xFF6E9E48));
    }
    final stem = Path()
      ..moveTo(b.dx, b.dy)
      ..quadraticBezierTo(b.dx + u * 0.01, b.dy - u * 0.16, b.dx + u * 0.07, b.dy - u * 0.14);
    _c.drawPath(stem, Paint()..style = PaintingStyle.stroke..color = const Color(0xFF6E9A4A)..strokeWidth = 1);
    for (var k = 0; k < 4; k++) {
      final f = 0.35 + k * 0.17;
      final p = Offset(b.dx + u * 0.075 * f + u * 0.005, b.dy - u * 0.14 * (1 - f * 0.15) + k * u * 0.012);
      _c.drawCircle(p + Offset(0, u * 0.02), u * 0.022, Paint()..color = const Color(0xFFF8F6EC));
      _c.drawCircle(p + Offset(0, u * 0.03), u * 0.008, Paint()..color = const Color(0xFFD8D4C0));
    }
  }

  void _flowerCluster(double cx, double cy, double z, int kind, int n, int seed) {
    final rng = Random(seed);
    final spots = <(double, double, double)>[];
    for (var i = 0; i < n; i++) {
      final a = rng.nextDouble() * 2 * pi, r = 0.015 + rng.nextDouble() * 0.05;
      spots.add((cx + cos(a) * r, cy + sin(a) * r, 0.85 + rng.nextDouble() * 0.3));
    }
    spots.sort((a, b) => _v.depth(a.$1, a.$2).compareTo(_v.depth(b.$1, b.$2)));
    for (final p in spots) {
      switch (kind) {
        case 0:
          _violet(p.$1, p.$2, z, p.$3);
        case 1:
          _primrose(p.$1, p.$2, z, p.$3);
        case 2:
          _daisy(p.$1, p.$2, z, p.$3);
        default:
          _lilyValley(p.$1, p.$2, z, p.$3);
      }
    }
  }

  void _petal(double x, double y, double z, double rot) {
    final b = _v.p(x, y, z);
    _c.save();
    _c.translate(b.dx, b.dy);
    _c.rotate(rot);
    _c.drawOval(Rect.fromCenter(center: Offset.zero, width: 7, height: 3.4), Paint()..color = const Color(0xFFF4B6C8));
    _c.restore();
  }

  /// 島の上を漂う蛍のような光
  void _fireflies() {
    for (var i = 0; i < 8; i++) {
      final rng = Random(i * 53 + 11);
      final bx = (rng.nextDouble() * 2 - 1) * 0.9;
      final by = (rng.nextDouble() * 2 - 1) * 0.9;
      final ph = rng.nextDouble() * pi * 2;
      final x = bx + sin(t * 0.3 + ph) * 0.08;
      final y = by + cos(t * 0.25 + ph) * 0.08;
      final z = 0.25 + rng.nextDouble() * 0.3 + sin(t * 0.6 + ph) * 0.04;
      final o = _v.p(x, y, z);
      final a = (0.35 + 0.35 * sin(t * 1.7 + ph * 3)).clamp(0.1, 0.8);
      _glow(o, _v.s * 0.05, a: a, color: const Color(0xFFFFE08A));
      _c.drawCircle(o, 1.1, _fill(const Color(0xFFFFF3C8).withValues(alpha: a + 0.2)));
    }
  }

  @override
  bool shouldRepaint(covariant IsoIslandPainter old) => true;
}
