import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/season_events.dart';
import '../data/species_database.dart';
import '../models/creature.dart';
import '../models/env_param.dart';
import '../providers/conservation_provider.dart';
import '../providers/species_provider.dart';
import '../services/real_weather.dart';
import '../widgets/creature_photo.dart';
import '../widgets/hint_dialog.dart';
import '../widgets/iso_island.dart';
import 'area_zoom_screen.dart';

const kGold = Color(0xFFE8B96A);
const kInk = Color(0xFF090806);

class HakoniwaScreen extends ConsumerStatefulWidget {
  const HakoniwaScreen({super.key});

  @override
  ConsumerState<HakoniwaScreen> createState() => _HakoniwaScreenState();
}

class _HakoniwaScreenState extends ConsumerState<HakoniwaScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  double _angle = 0.0; // 島の回転（ラジアン）
  Timer? _discoverTimer;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60))
      ..repeat();
    CreaturePhotos.preload(SpeciesDatabase.instance.all)
        .then((_) => mounted ? setState(() {}) : null);
    // 現実の天気（予報）を取得して、季節・気温・最初の予報に反映する
    _discoverTimer = Timer.periodic(const Duration(seconds: 1), (_) => _discoverTick());
    // 参考にする場所に合わせて、生き物の分布を決める
    ref.listenManual(placeProvider, (_, next) {
      ref.read(conservationProvider.notifier).setPlaces(next);
    }, fireImmediately: true);
    ref.listenManual(realInfoProvider, (_, next) {
      next.whenData((m) => ref.read(conservationProvider.notifier).applyRealInfo(m));
    }, fireImmediately: true);
  }

  /// いま姿を見せている生き物を、図鑑に登録する
  void _discoverTick() {
    if (!mounted) return;
    final s = ref.read(conservationProvider);
    final n = ref.read(conservationProvider.notifier);
    final all = SpeciesDatabase.instance.all;
    final t = _clock.value * 60;
    final seen = <String>[];
    for (final h in isoLayout) {
      for (final c in IsoIslandPainter.habitatSpecies(h, s, n, all)) {
        if (!s.discovered.contains(c.id) &&
            IsoIslandPainter.presenceAlpha(c, t, s.turn, s.population[c.id] ?? 0) > 0.5) {
          seen.add(c.id);
        }
      }
    }
    if (seen.isNotEmpty) n.markDiscovered(seen);
  }

  @override
  void dispose() {
    _discoverTimer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0E0C09),
        title: const Text('最初からやり直しますか？', style: TextStyle(color: kGold)),
        content: const Text('いまの進行（環境・個体数・予算）は元に戻り、1年目の最初から始まります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('やめる')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('リセット')),
        ],
      ),
    );
    if (ok == true) ref.read(conservationProvider.notifier).restart();
  }

  void _openArea(Habitat h) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AreaZoomScreen(habitat: h)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(conservationProvider);
    final n = ref.read(conservationProvider.notifier);
    final all = ref.watch(allCreaturesProvider);

    ref.listen(conservationProvider.select((v) => v.finished), (_, done) {
      if (done) _showResult();
    });
    listenSeasonEvents(context, ref);
    listenDiscoveries(context, ref);

    final aliveRatio = all.isEmpty ? 0.0 : s.aliveCount / all.length;

    return Scaffold(
      backgroundColor: kInk,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(state: s, total: s.total, onReset: _confirmReset),
            const WeatherBar(),
            const EventBanner(),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final size = Size(c.maxWidth, c.maxHeight);
                return GestureDetector(
                  onPanUpdate: (d) => setState(() => _angle += d.delta.dx * 0.008),
                  onTapUp: (d) {
                    final h = IsoView(size, _angle).hit(d.localPosition);
                    if (h != null) _openArea(h);
                  },
                  child: AnimatedBuilder(
                    animation: _clock,
                    builder: (_, __) => CustomPaint(
                      size: size,
                      painter: IsoIslandPainter(
                        state: s,
                        creatures: all,
                        notifier: n,
                        aliveRatio: aliveRatio,
                        t: _clock.value * 60,
                        angle: _angle,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('ドラッグで回転 / エリアをタップで拡大',
                  style: TextStyle(fontSize: 10, color: Colors.white30)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
              child: Text(
                s.log.first,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: s.finished ? n.restart : n.nextTurn,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kGold,
                    side: const BorderSide(color: kGold, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                  ),
                  child: Text(s.finished ? 'もう一度はじめる' : '季節をすすめる',
                      style: const TextStyle(letterSpacing: 4, fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showResult() {
    final s = ref.read(conservationProvider);
    final reachable = s.total;
    final found = s.foundNow.length;
    final rate = reachable == 0 ? 0.0 : found / reachable;
    final rank = rate >= 0.8 ? 'S 博物学者' : rate >= 0.6 ? 'A 探検家' : rate >= 0.4 ? 'B 観察者' : 'C 見習い';
    final newDex = s.discovered.length - s.dexAtStart;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0E0C09),
        title: Text('調査の結果  $rank', style: const TextStyle(color: kGold)),
        content: Text('今回出会えた種：$found / $reachable（この場所で出会える種）\n'
            '図鑑に新しく載った種：$newDex\n'
            '図鑑：${s.discovered.length} / ${s.dexTotal}\n\n'
            '場所や条件を変えて、まだ出会っていない種を探してみよう。', style: const TextStyle(height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 上部バー
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final ConservationState state;
  final int total;
  final VoidCallback onReset;
  const _TopBar({required this.state, required this.total, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 20, 8),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.home_outlined, size: 18, color: kGold),
            label: const Text('トップ', style: TextStyle(color: kGold, fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              side: BorderSide(color: kGold.withValues(alpha: 0.5)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            state.finished ? '結果' : '${state.year}年目  ${state.seasonLabel}',
            style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 3),
          ),
          const Spacer(),
          _chip('出会い', '${state.foundNow.length}/$total'),
          const SizedBox(width: 12),
          _chip('図鑑', '${state.discovered.length}/${state.dexTotal}'),
          const SizedBox(width: 12),
          _chip('予算', '${state.budget}'),
          IconButton(
            tooltip: '最初からやり直す',
            icon: const Icon(Icons.restart_alt, color: kGold),
            onPressed: onReset,
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          Text(value, style: const TextStyle(color: kGold, fontSize: 16)),
        ],
      );
}

// ---------------------------------------------------------------------------
// エリア詳細シート（パラメータ調整・種の一覧）
// ---------------------------------------------------------------------------

/// 操作（コマンド）のアイコン
IconData commandIcon(EnvParam p) {
  switch (p) {
    case EnvParam.ph: return Icons.science_outlined;
    case EnvParam.moisture: return Icons.water_drop_outlined;
    case EnvParam.nutrients: return Icons.grass;
    case EnvParam.temperature: return Icons.thermostat;
    case EnvParam.sunlight: return Icons.wb_sunny_outlined;
    case EnvParam.salinity: return Icons.waves;
    case EnvParam.oxygen: return Icons.bubble_chart_outlined;
    case EnvParam.flow: return Icons.moving;
    case EnvParam.elevation: return Icons.terrain;
    case EnvParam.pollution: return Icons.cleaning_services_outlined;
  }
}

/// エリアの操作パネル：診断（原因とおすすめ）→ コマンド → くわしい数値（読み取り専用）→ 種の一覧
class AreaPanel extends ConsumerWidget {
  final Habitat habitat;
  final bool showSpecies;
  const AreaPanel({super.key, required this.habitat, this.showSpecies = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(conservationProvider);
    final n = ref.read(conservationProvider.notifier);
    final all = ref.watch(allCreaturesProvider);
    final area = s.areas[habitat]!;
    final hints = n.diagnose(habitat);
    final species = all.where((c) => c.habitats.contains(habitat)).toList()
      ..sort((a, b) => a.type.index.compareTo(b.type.index));

    bool recommended(EnvParam p, int dir) => hints.any((h) => h.param == p && h.direction == dir);

    Widget command(String label, int cost, IconData icon, VoidCallback? onTap, {bool hot = false}) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text('$label  $cost', style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: hot ? Colors.black : Colors.white70,
          backgroundColor: hot ? kGold : Colors.transparent,
          side: BorderSide(color: hot ? kGold : Colors.white24),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(0, 34),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            Text(habitat.label + (area.protectedArea ? '（保護区）' : ''),
                style: const TextStyle(fontSize: 22, color: kGold, letterSpacing: 4)),
            const Spacer(),
            Text('予算 ${s.budget}', style: const TextStyle(color: Colors.white70)),
          ],
        ),
        PlaceLine(habitat: habitat),
        if (habitat.isMountain) ElevationSetting(habitat: habitat),
        const SizedBox(height: 10),
        const _SectionTitle('診断'),
        if (hints.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('いまのところ大きな問題はありません', style: TextStyle(fontSize: 12, color: Colors.white54)),
          )
        else
          for (final h in hints)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFE08A5A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${h.text}（${h.count}種が弱っています）',
                        style: const TextStyle(fontSize: 12.5, height: 1.3)),
                  ),
                  command(h.command, h.param.cost, commandIcon(h.param),
                      s.budget >= h.param.cost ? () => n.adjust(habitat, h.param, h.direction) : null,
                      hot: true),
                ],
              ),
            ),
        const SizedBox(height: 8),
        const _SectionTitle('コマンド'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in habitat.params)
              for (final dir in const [1, -1])
                if (!(p == EnvParam.pollution && dir > 0))
                  command(dir > 0 ? p.actionUp : p.actionDown, p.cost, commandIcon(p),
                      s.budget >= p.cost ? () => n.adjust(habitat, p, dir) : null,
                      hot: recommended(p, dir)),
            command('障害物を撤去（${area.obstacles}個）', ConservationNotifier.removeObstacleCost,
                Icons.delete_sweep_outlined,
                area.obstacles > 0 && s.budget >= ConservationNotifier.removeObstacleCost
                    ? () => n.removeObstacle(habitat)
                    : null),
            if (!area.protectedArea)
              command('保護区にする', 40, Icons.shield_outlined,
                  s.budget >= 40 ? () => n.protect(habitat) : null),
          ],
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('くわしい数値（参考）', style: TextStyle(fontSize: 12, color: Colors.white54)),
            children: [for (final p in habitat.params) ParamRow(param: p, value: area[p])],
          ),
        ),
        if (showSpecies) ...[
          const Divider(color: Colors.white12),
          for (final c in species) SpeciesRow(creature: c, habitat: habitat),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white38, letterSpacing: 4)),
      );
}

/// 数値は読み取り専用（直接は変えられない）
class ParamRow extends StatelessWidget {
  final EnvParam param;
  final double value;
  const ParamRow({super.key, required this.param, required this.value});

  @override
  Widget build(BuildContext context) {
    final isPollution = param == EnvParam.pollution;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 118, child: Text(param.label, style: const TextStyle(fontSize: 12, color: Colors.white70))),
          Expanded(
            child: LinearProgressIndicator(
              value: (value - param.min) / (param.max - param.min),
              minHeight: 3,
              color: isPollution ? const Color(0xFFB5733A) : kGold,
              backgroundColor: Colors.white10,
            ),
          ),
          SizedBox(
            width: 54,
            child: Text(param.format(value), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// 現実の場所の選択（フィールドごとに、天気などの参考にする場所を選ぶ）
Future<void> showPlaceDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => Consumer(builder: (context, ref, _) {
      final places = ref.watch(placeProvider);
      return AlertDialog(
        backgroundColor: const Color(0xFF0E0C09),
        title: const Text('参考にする現実の場所', style: TextStyle(color: kGold, fontSize: 16, letterSpacing: 2)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('フィールドごとに、現実の天気（予報）などを参考にする場所を選べます。',
                  style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.4)),
              const SizedBox(height: 10),
              for (final h in [Habitat.mountainHigh, Habitat.mountainMid, Habitat.mountainLow, Habitat.forest, Habitat.pond, Habitat.river, Habitat.ocean])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 64, child: Text(h.label, style: const TextStyle(color: kGold, fontSize: 12))),
                      Expanded(child: PlaceChooser(habitat: h, place: places[h]!)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Text('池は管理された水域として、天気だけを参考にします。海は海面水温・海流・波、川は河川流量、山は標高補正の気温も反映します。赤潮は、水温・波・雨からの推定です。',
                  style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.4)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる')),
        ],
      );
    }),
  );
}

class PlaceChooser extends ConsumerWidget {
  final Habitat habitat;
  final Place place;
  const PlaceChooser({super.key, required this.habitat, required this.place});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<Place>(
      tooltip: '場所を選ぶ',
      color: const Color(0xFF14110C),
      onSelected: (p) {
        final cur = ref.read(placeProvider);
        ref.read(placeProvider.notifier).state = {...cur, habitat: p};
        // 山は、開始前なら場所の標高を初期値にする
        if (habitat.isMountain) {
          ref.read(conservationProvider.notifier).setElevation(habitat, p.elevation);
        }
      },
      itemBuilder: (_) => [
        for (final p in placePresets[habitat]!)
          PopupMenuItem(
            value: p,
            child: Text(habitat.isMountain ? '${p.name}（${p.elevation.round()}m）' : p.name),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(4)),
        child: Row(
          children: [
            Expanded(child: Text(place.name, style: const TextStyle(fontSize: 13))),
            const Icon(Icons.arrow_drop_down, size: 18, color: kGold),
          ],
        ),
      ),
    );
  }
}

/// エリアの操作パネルに出す：参照している現実の場所と、その場所固有の現実の情報
class PlaceLine extends ConsumerWidget {
  final Habitat habitat;
  const PlaceLine({super.key, required this.habitat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(placeProvider)[habitat]!;
    final info = ref.watch(realInfoProvider).valueOrNull?[habitat];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 14, color: kGold),
              const SizedBox(width: 4),
              Text('参考にする現実の場所：', style: const TextStyle(fontSize: 11, color: Colors.white54)),
              SizedBox(width: 150, child: PlaceChooser(habitat: habitat, place: place)),
            ],
          ),
          if (info != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 18),
              child: Text(
                [
                  '${info.label} ${info.temp.round()}℃',
                  if (habitat != Habitat.pond && info.extraLine != null) info.extraLine!,
                ].join(' ／ '),
                style: const TextStyle(fontSize: 11, color: Colors.white54, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

/// 山のステージの標高の設定（ゲーム開始前のみ。ステージごとに範囲が違う）
class ElevationSetting extends ConsumerWidget {
  final Habitat habitat;
  const ElevationSetting({super.key, required this.habitat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(conservationProvider);
    final n = ref.read(conservationProvider.notifier);
    final elev = s.areas[habitat]![EnvParam.elevation];
    final locked = s.turn != 0;
    final (lo, hi) = habitat.elevationBand;
    final levels = [for (var i = 0; i < 4; i++) (lo + (hi - lo) * (i + 0.5) / 4).roundToDouble()];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('標高 ${elev.round()}m（この段の範囲 ${lo.round()}〜${hi.round()}m） ${locked ? '開始後は変えられません' : '開始前に設定できます'}',
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final m in levels)
                ChoiceChip(
                  label: Text('${m.round()}m', style: const TextStyle(fontSize: 11)),
                  selected: (elev - m).abs() < (hi - lo) / 8,
                  onSelected: locked ? null : (_) => n.setElevation(habitat, m),
                  selectedColor: kGold.withValues(alpha: 0.3),
                  backgroundColor: Colors.transparent,
                  side: const BorderSide(color: Colors.white24),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// いまの現実の天気（森の参考地点）と、場所の設定
class WeatherBar extends ConsumerWidget {
  const WeatherBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(realInfoProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
      child: Row(
        children: [
          w.when(
            data: (m) {
              final d = m[Habitat.forest] ?? m.values.first;
              return Expanded(
                child: Row(
                  children: [
                    Icon(d.icon, size: 16, color: kGold),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('現実の天気  ${d.summary}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.white60)),
                    ),
                  ],
                ),
              );
            },
            loading: () => const Expanded(
                child: Text('現実の天気を取得中…', style: TextStyle(fontSize: 11, color: Colors.white38))),
            error: (_, __) => const Expanded(
                child: Text('天気を取得できませんでした（日付の季節で進行します）',
                    style: TextStyle(fontSize: 11, color: Colors.white38))),
          ),
          TextButton.icon(
            onPressed: () => showPlaceDialog(context),
            icon: const Icon(Icons.place_outlined, size: 14, color: kGold),
            label: const Text('場所', style: TextStyle(fontSize: 11, color: kGold)),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 28)),
          ),
        ],
      ),
    );
  }
}

class SpeciesRow extends ConsumerWidget {
  final Creature creature;
  final Habitat habitat;
  const SpeciesRow({super.key, required this.creature, required this.habitat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(conservationProvider);
    final n = ref.read(conservationProvider.notifier);
    final pop = s.population[creature.id] ?? 0;
    final fit = n.suitability(creature, habitat);
    final absent = s.absent.contains(creature.id);
    final extinct = pop == 0 && !absent;

    if (!s.discovered.contains(creature.id)) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const CircleAvatar(
          radius: 20,
          backgroundColor: Color(0xFF1C1710),
          child: Icon(Icons.help_outline, color: Colors.white38),
        ),
        title: const Text('？？？', style: TextStyle(color: Colors.white54, letterSpacing: 4)),
        subtitle: Text(absent ? 'この場所では出会えない' : 'まだ出会っていない（タップでヒント）',
            style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.lightbulb_outline, size: 16, color: kGold),
        onTap: () => showHintDialog(context, ref, creature),
      );
    }

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CreatureThumb(creature: creature, size: 40, dim: extinct || absent),
      title: Text(creature.nameJa,
          style: TextStyle(
            decoration: extinct ? TextDecoration.lineThrough : null,
            color: (extinct || absent) ? Colors.white38 : null,
          )),
      subtitle: Text(absent ? 'この地域には分布しません' : (extinct ? '絶滅' : '${creature.redLabel != null ? '${creature.endangered ? '★' : ''}${creature.redLabel}　' : ''}個体数 $pop ／ 適合度 ${(fit * 100).round()}%'),
          style: const TextStyle(fontSize: 11)),
      trailing: extinct
          ? TextButton(
              onPressed: s.budget >= n.reintroduceCost(creature)
                  ? () => n.reintroduce(creature)
                  : null,
              child: Text('再導入 (${n.reintroduceCost(creature)})'),
            )
          : null,
      onTap: () => showCreatureDetail(context, creature),
    );
  }
}


// ---------------------------------------------------------------------------
// 出来事（予報・発生）
// ---------------------------------------------------------------------------

/// 次の季節の予報と、直前に起きた出来事を表示する
class EventBanner extends ConsumerWidget {
  const EventBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(conservationProvider);
    final pending = findSeasonEvent(s.pendingEvent);
    if (s.finished) return const SizedBox.shrink();
    if (pending == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('来季の予報：穏やか',
              style: TextStyle(fontSize: 11, color: Colors.white38)),
        ),
      );
    }
    final color = pending.positive ? const Color(0xFF7FD6A0) : const Color(0xFFE08A5A);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(pending.icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('予報：${pending.title}${s.pendingFromReal ? '（現実の天気予報）' : ''}',
                    style: TextStyle(fontSize: 12, color: color, letterSpacing: 1)),
                Text(s.pendingFromReal && s.weatherNote != null ? '${s.weatherNote}。${pending.forecast}' : pending.forecast,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.white60, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 出来事が起きたら、いま表示中の画面にダイアログを出す（二重表示を避ける）
void listenSeasonEvents(BuildContext context, WidgetRef ref) {
  ref.listen(conservationProvider.select((v) => (v.turn, v.lastEvent)), (prev, next) {
    final ev = findSeasonEvent(next.$2);
    if (ev == null || prev?.$1 == next.$1) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final color = ev.positive ? const Color(0xFF7FD6A0) : const Color(0xFFE08A5A);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0E0C09),
        icon: Icon(ev.icon, size: 36, color: color),
        title: Text(ev.title, style: TextStyle(color: color, letterSpacing: 3)),
        content: Text(ev.result, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  });
}


/// 新しく図鑑に登録されたら知らせる（いま表示中の画面にだけ）
void listenDiscoveries(BuildContext context, WidgetRef ref) {
  ref.listen(conservationProvider.select((v) => v.discovered), (prev, next) {
    final added = next.difference(prev ?? <String>{});
    if (added.isEmpty || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final rare = [
      for (final c in SpeciesDatabase.instance.all)
        if (added.contains(c.id) && c.endangered) c,
    ];
    if (rare.isNotEmpty) {
      showRareDialog(context, rare);
      return;
    }
    final names = [
      for (final c in SpeciesDatabase.instance.all)
        if (added.contains(c.id)) c.nameJa,
    ];
    final text = names.length <= 3 ? names.join('、') : '${names.take(3).join('、')} ほか${names.length - 3}種';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF14110C),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.menu_book, size: 18, color: kGold),
            const SizedBox(width: 8),
            Expanded(child: Text('図鑑に登録：$text', style: const TextStyle(color: Colors.white))),
          ],
        ),
      ));
  });
}


/// 絶滅危惧種を見つけたときの、金色の特別な演出
Future<void> showRareDialog(BuildContext context, List<Creature> list) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: const Color(0xFF0E0C09),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: kGold, width: 1.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: [kGold.withValues(alpha: 0.28), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, color: kGold, size: 30),
            const SizedBox(height: 6),
            const Text('絶滅危惧種を発見！',
                style: TextStyle(color: kGold, fontSize: 20, letterSpacing: 4, shadows: [Shadow(blurRadius: 14, color: kGold)])),
            const SizedBox(height: 12),
            for (final c in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CreatureThumb(creature: c, size: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.nameJa, style: const TextStyle(fontSize: 16)),
                          Text('${c.redLabel}　予算 +${c.discoveryBonus}',
                              style: const TextStyle(fontSize: 12, color: kGold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            const Text('図鑑に登録しました。大切に守りましょう。',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      ),
    ),
  );
}
