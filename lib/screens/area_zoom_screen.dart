import 'dart:async';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/species_database.dart';
import '../models/creature.dart';
import '../providers/conservation_provider.dart';
import '../providers/species_provider.dart';
import '../widgets/creature_photo.dart';
import '../widgets/hint_dialog.dart';
import '../widgets/iso_island.dart';
import 'hakoniwa_screen.dart';

/// エリア拡大画面：選んだエリアを擬似3Dで大きく映し、生きものを写真で表示する。
/// ドラッグで回転、写真をタップで詳細。下半分でパラメータ調整。
class AreaZoomScreen extends ConsumerStatefulWidget {
  final Habitat habitat;
  const AreaZoomScreen({super.key, required this.habitat});

  @override
  ConsumerState<AreaZoomScreen> createState() => _AreaZoomScreenState();
}

class _AreaZoomScreenState extends ConsumerState<AreaZoomScreen>
    with SingleTickerProviderStateMixin {
  Widget _zoomButton(IconData icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: const Color(0xCC14110C),
          shape: CircleBorder(side: BorderSide(color: kGold.withValues(alpha: 0.6))),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(7), child: Icon(icon, size: 18, color: kGold)),
          ),
        ),
      );

  late final AnimationController _clock;
  double _angle = 0.0;
  Timer? _discoverTimer;
  double _zoom = 0.75; // 小さめに全体を見せ、必要なら拡大する
  Offset _pan = Offset.zero;
  double _zoomAtStart = 0.75;
  bool _listMode = false; // true=写真カードの一覧 / false=3D表示（最初は3D）

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60))
      ..repeat();
    CreaturePhotos.preload(SpeciesDatabase.instance.all)
        .then((_) => mounted ? setState(() {}) : null);
    _discoverTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final s = ref.read(conservationProvider);
      final n = ref.read(conservationProvider.notifier);
      final t = _clock.value * 60;
      final seen = [
        for (final c in IsoIslandPainter.habitatSpecies(widget.habitat, s, n, SpeciesDatabase.instance.all))
          if (!s.foundNow.contains(c.id) &&
              IsoIslandPainter.presenceAlpha(c, t, s.turn, s.population[c.id] ?? 0) > 0.5)
            c.id,
      ];
      if (seen.isNotEmpty) n.markDiscovered(seen);
    });
  }

  @override
  void dispose() {
    _discoverTimer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  void _onTap(Offset pos, Size size) {
    final s = ref.read(conservationProvider);
    final n = ref.read(conservationProvider.notifier);
    final all = SpeciesDatabase.instance.all;
    final v = IsoView(size, _angle, focus: widget.habitat, zoom: _zoom, pan: _pan);
    final spots = IsoIslandPainter.medallionPlacements(
        v, widget.habitat, s, n, all, _clock.value * 60);

    Creature? hit;
    var bestD = double.infinity;
    for (final (c, center, rad) in spots) {
      final d = (center - pos).distance;
      if (d < rad * 1.3 && d < bestD) {
        hit = c;
        bestD = d;
      }
    }
    if (hit != null) showCreatureDetail(context, hit);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(conservationProvider);
    final n = ref.read(conservationProvider.notifier);
    final h = widget.habitat;
    final all = ref.watch(allCreaturesProvider);
    listenSeasonEvents(context, ref);
    listenDiscoveries(context, ref);

    return Scaffold(
      backgroundColor: kInk,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 14, color: kGold),
                    label: const Text('箱庭へ', style: TextStyle(color: kGold, fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      side: BorderSide(color: kGold.withValues(alpha: 0.5)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${h.label}  ${s.year}年目 ${s.seasonLabel}',
                      style: const TextStyle(fontSize: 18, letterSpacing: 3)),
                  const Spacer(),
                  Text('予算 ${s.budget}', style: const TextStyle(color: kGold)),
                ],
              ),
            ),
            const EventBanner(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  foregroundColor: Colors.white54,
                  selectedForegroundColor: kGold,
                  selectedBackgroundColor: const Color(0xFF1C1710),
                  side: BorderSide(color: kGold.withValues(alpha: 0.4)),
                ),
                segments: const [
                  ButtonSegment(value: true, label: Text('一覧'), icon: Icon(Icons.grid_view, size: 16)),
                  ButtonSegment(value: false, label: Text('3D表示'), icon: Icon(Icons.view_in_ar, size: 16)),
                ],
                selected: {_listMode},
                onSelectionChanged: (v) => setState(() => _listMode = v.first),
              ),
            ),
            if (_listMode) ...[
              Expanded(flex: 5, child: _SpeciesGrid(habitat: h)),
              Expanded(flex: 4, child: AreaPanel(habitat: h, showSpecies: false)),
            ] else ...[
            LayoutBuilder(builder: (context, c) {
              final w = min(c.maxWidth, 460.0);
              final size = Size(w, w * 0.9);
              return Center(
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRect(
                          child: Listener(
                            onPointerSignal: (e) {
                              if (e is PointerScrollEvent) {
                                setState(() => _zoom =
                                    (_zoom * exp(-e.scrollDelta.dy * 0.0015)).clamp(0.5, 3.0));
                              }
                            },
                            child: GestureDetector(
                              onScaleStart: (_) => _zoomAtStart = _zoom,
                              onScaleUpdate: (d) => setState(() {
                                if (d.pointerCount >= 2) {
                                  _zoom = (_zoomAtStart * d.scale).clamp(0.5, 3.0);
                                  _pan += d.focalPointDelta;
                                } else {
                                  _angle += d.focalPointDelta.dx * 0.008;
                                  _pan += Offset(0, d.focalPointDelta.dy);
                                }
                              }),
                              onTapUp: (d) => _onTap(d.localPosition, size),
                              child: AnimatedBuilder(
                                animation: _clock,
                                builder: (_, __) => CustomPaint(
                                  size: size,
                                  painter: IsoIslandPainter(
                                    state: s,
                                    creatures: all,
                                    notifier: n,
                                    aliveRatio: 0,
                                    t: _clock.value * 60,
                                    angle: _angle,
                                    focus: h,
                                    zoom: _zoom,
                                    pan: _pan,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Column(
                          children: [
                            _zoomButton(Icons.add, () => setState(() => _zoom = (_zoom * 1.25).clamp(0.5, 3.0))),
                            _zoomButton(Icons.remove, () => setState(() => _zoom = (_zoom / 1.25).clamp(0.5, 3.0))),
                            _zoomButton(Icons.center_focus_strong, () => setState(() {
                                  _zoom = 0.75;
                                  _pan = Offset.zero;
                                  _angle = 0;
                                })),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('ドラッグで回転・＋−で拡大 ／ 動物は珍しさに応じて、ときどき姿を見せます（全種は「一覧」で）',
                  style: TextStyle(fontSize: 10, color: Colors.white30)),
            ),
              Expanded(child: AreaPanel(habitat: h)),
            ],
          ],
        ),
      ),
    );
  }
}


/// 写真カードの一覧（絶滅した種は白黒で表示し、再導入できる）
class _SpeciesGrid extends ConsumerWidget {
  final Habitat habitat;
  const _SpeciesGrid({required this.habitat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(conservationProvider);
    final n = ref.read(conservationProvider.notifier);
    final all = ref.watch(allCreaturesProvider);
    // 3D表示と同じ数だけ出す。加えて、絶滅した発見済みの種は再導入できるように残す
    final shown = IsoIslandPainter.habitatSpecies(habitat, s, n, all).map((c) => c.id).toSet();
    final species = all
        .where((c) =>
            shown.contains(c.id) ||
            (c.habitats.contains(habitat) &&
                s.discovered.contains(c.id) &&
                (s.population[c.id] ?? 0) <= 0))
        .toList()
      ..sort((a, b) => a.type.index.compareTo(b.type.index));

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.82,
      ),
      itemCount: species.length,
      itemBuilder: (_, i) {
        final c = species[i];
        final pop = s.population[c.id] ?? 0;
        final fit = n.suitability(c, habitat).clamp(0.0, 1.0);
        final known = s.discovered.contains(c.id);
        if (!known) {
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => showHintDialog(context, ref, c),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF14110C),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.help_outline, color: Colors.white24, size: 36),
                  SizedBox(height: 4),
                  Text('？？？', style: TextStyle(fontSize: 11, color: Colors.white54)),
                  Text('ヒント', style: TextStyle(fontSize: 9, color: Color(0xFFE8B96A))),
                ],
              ),
            ),
          );
        }
        final absent = s.absent.contains(c.id);
        final extinct = pop == 0 && !absent && s.foundNow.contains(c.id);
        final waiting = pop == 0 && !absent && !extinct;
        final ring = Color.lerp(const Color(0xFFB5533A), kGold, fit)!;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showCreatureDetail(context, c),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF14110C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ((extinct || absent || waiting) ? Colors.white12 : ring).withValues(alpha: 0.6)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, c2) => CreatureThumb(
                      creature: c,
                      size: min(c2.maxWidth, c2.maxHeight),
                      dim: extinct || absent || waiting,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  c.nameJa,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: (extinct || absent || waiting) ? Colors.white38 : Colors.white,
                    decoration: extinct ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (absent)
                  const Text('分布外', style: TextStyle(fontSize: 9, color: Colors.white30))
                else if (waiting)
                  const Text('まだ来ていません', style: TextStyle(fontSize: 9, color: Colors.white30))
                else if (extinct)
                  SizedBox(
                    height: 22,
                    child: TextButton(
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero, minimumSize: Size.zero),
                      onPressed: s.budget >= n.reintroduceCost(c) ? () => n.reintroduce(c) : null,
                      child: Text('再導入 ${n.reintroduceCost(c)}',
                          style: const TextStyle(fontSize: 10)),
                    ),
                  )
                else
                  Text('個体数 $pop ・ ${(fit * 100).round()}%',
                      style: TextStyle(fontSize: 9, color: ring)),
              ],
            ),
          ),
        );
      },
    );
  }
}
