import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/creature.dart';
import '../providers/conservation_provider.dart';
import '../services/real_weather.dart';

/// 「今日の条件なら、どこにどんな生きものが出やすいか」を決める。
/// 要素：時間帯（活動する時間） × 雨への反応 × エリア間のつながり
///   ・山で雨が降ると、川の魚が動く／川の栄養が海に流れ込み、ベイト（小魚）が寄る
///   ・ベイトが多いと、それを追う回遊魚・海鳥が増える
///   ・海が荒れると、海の生きものは見えにくい
/// 出るかどうかは「出現率」で決め、同じ時間帯のあいだは結果が変わらない（ちらつかない）。

enum DayPart {
  dawn,
  day,
  dusk,
  night;

  String get label => const ['朝', '昼', '夕方', '夜'][index];
}

DayPart partOfHour(int h) {
  if (h >= 4 && h < 8) return DayPart.dawn;
  if (h >= 8 && h < 16) return DayPart.day;
  if (h >= 16 && h < 19) return DayPart.dusk;
  return DayPart.night;
}

/// 時間帯を手動で指定する（null=いまの時刻）。「夕方に行くなら？」を試せる
final timeOverrideProvider = StateProvider<DayPart?>((ref) => null);

/// 1分ごとに更新する現在時刻
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});

/// いまの条件（時間帯・各エリアの現実の雨と風）
class ActivityContext {
  final DateTime time;
  final DayPart part;
  final bool manual;
  final Map<Habitat, double> wet; // 直近の雨の多さ 0〜1（直近3日で15mm以上=1）
  final Map<Habitat, double> rainMm;
  final Map<Habitat, bool> pouring; // いま降っている
  final Map<Habitat, double> wind; // m/s

  const ActivityContext({
    required this.time,
    required this.part,
    this.manual = false,
    this.wet = const {},
    this.rainMm = const {},
    this.pouring = const {},
    this.wind = const {},
  });

  static ActivityContext current =
      ActivityContext(time: DateTime.now(), part: partOfHour(DateTime.now().hour));

  double wetOf(Habitat h) => wet[h] ?? 0.35; // 取得できなければ「ふつう」
  bool pourOf(Habitat h) => pouring[h] ?? false;
  double windOf(Habitat h) => wind[h] ?? 0;

  /// 山・森の雨（川の上流側）
  double get upstreamWet {
    const hs = [Habitat.forest, Habitat.mountainLow, Habitat.mountainMid, Habitat.mountainHigh];
    final v = [for (final h in hs) if (wet.containsKey(h)) wet[h]!];
    return v.isEmpty ? 0.35 : v.reduce(max);
  }

  bool get hasWeather => wet.isNotEmpty;

  /// そのエリアの今日の条件の一行まとめ
  String summary(Habitat h) {
    final p = <String>['${part.label}${manual ? '(指定)' : ''}'];
    if (hasWeather) {
      if (pourOf(h)) {
        p.add('雨が降っている');
      } else if (wetOf(h) >= 0.5) {
        p.add('雨のあと(直近3日で${(rainMm[h] ?? 0).round()}mm)');
      } else if (wetOf(h) >= 0.2) {
        p.add('少し雨があった');
      } else {
        p.add('雨なし');
      }
      if (h == Habitat.river && upstreamWet >= 0.5) p.add('山で雨(川に流れ込む)');
      if (h == Habitat.ocean && wetOf(Habitat.river) >= 0.5) p.add('川から栄養が流れ込む');
      if (h == Habitat.ocean && windOf(h) >= 8) p.add('海が荒れ気味');
    } else {
      p.add('天気は未取得');
    }
    return p.join(' ・ ');
  }
}

/// 時刻と現実の天気から、いまの条件を作る。読むだけで、画面を更新させたいときに watch する
final activityProvider = Provider<ActivityContext>((ref) {
  final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
  final manual = ref.watch(timeOverrideProvider);
  final info = ref.watch(realInfoProvider).valueOrNull ?? const {};
  final wet = <Habitat, double>{};
  final mm = <Habitat, double>{};
  final pour = <Habitat, bool>{};
  final wind = <Habitat, double>{};
  info.forEach((h, w) {
    wet[h] = (w.precipPast3 / 15).clamp(0.0, 1.0).toDouble();
    mm[h] = w.precipPast3;
    final c = w.code;
    pour[h] = w.precip >= 1.0 || (c >= 61 && c <= 67) || (c >= 80 && c <= 82) || c >= 95;
    wind[h] = w.wind;
  });
  final ctx = ActivityContext(
    time: now,
    part: manual ?? partOfHour(now.hour),
    manual: manual != null,
    wet: wet,
    rainMm: mm,
    pouring: pour,
    wind: wind,
  );
  ActivityContext.current = ctx; // 描画側（painter）が読む
  return ctx;
});

// ---- 種ごとの設定 ---------------------------------------------------------

const _all = {DayPart.dawn, DayPart.day, DayPart.dusk, DayPart.night};
const _diurnal = {DayPart.dawn, DayPart.day, DayPart.dusk};
const _dayOnly = {DayPart.day};
const _nocturnal = {DayPart.dusk, DayPart.night};
const _crepNight = {DayPart.dawn, DayPart.dusk, DayPart.night};
const _crep = {DayPart.dawn, DayPart.dusk};

/// 活動する時間帯（書いていない種は、種類ごとの標準：植物・魚=いつでも、鳥・動物=昼行性）
const Map<String, Set<DayPart>> speciesParts = {
  // 夜行性・薄明薄暮性の哺乳類
  'tanuki': _crepNight, 'kitsune': _crepNight, 'kitakitsune': _crepNight,
  'anaguma': _nocturnal, 'honden': _crepNight, 'itachi': _crepNight,
  'musasabi': _nocturnal, 'momonga': _nocturnal, 'yamane': _nocturnal,
  'akanezumi': _nocturnal, 'abura_koumori': _nocturnal,
  'iriomote': _crepNight, 'tsushima_yamaneko': _crepNight, 'amami_kurousagi': _nocturnal,
  'inoshishi': _crepNight, 'nousagi': _crepNight,
  'nihonjika': _crep, 'ezoshika': _crep,
  // 両生類・爬虫類
  'amagaeru': _nocturnal, 'hikigaeru': _nocturnal, 'moriao': _nocturnal,
  'tonosama': {DayPart.day, DayPart.dusk, DayPart.night},
  'akahara_imori': _all,
  'hakone_sansho': {DayPart.night}, 'osansho': {DayPart.night},
  'ishigame': _dayOnly, 'kanahebi': _dayOnly,
  // 昆虫
  'oomurasaki': _dayOnly, 'asagimadara': _dayOnly, 'namiageha': _dayOnly,
  'monshiro': _dayOnly, 'gifuchou': _dayOnly,
  'oniyanma': _dayOnly, 'ginyanma': _dayOnly, 'akiakane': _dayOnly,
  'genji_hotaru': _nocturnal, 'heike_hotaru': _nocturnal,
  'kabutomushi': _nocturnal, 'nokogiri_kuwagata': _nocturnal,
  'miyama_kuwagata': _nocturnal, 'ookuwagata': _nocturnal,
  // 夜・薄暮の鳥
  'fukurou': _nocturnal, 'ooshima_fukurou': _nocturnal,
  'hototogisu': _crepNight, 'goisagi': _nocturnal, 'shigi': _crep,
  // 夜に動く魚
  'unagi': _nocturnal, 'namazu': _nocturnal, 'donko': _nocturnal,
  'dojo': _nocturnal, 'hotokedojo': _nocturnal, 'kajika': _nocturnal,
  'kasago': _nocturnal, 'mebaru': _nocturnal, 'tachiuo': _nocturnal,
  'suzuki': _crepNight,
};

/// 雨への反応（-1=雨を避ける … 0=関係なし … +1=雨のあとに活発）。書いていない種は種類ごとの標準
const Map<String, double> speciesRain = {
  // 雨のあとに出る
  'amagaeru': 1, 'hikigaeru': 1, 'moriao': 1, 'hakone_sansho': 1,
  'tonosama': 0.5, 'akahara_imori': 0.5, 'osansho': 0.5,
  'genji_hotaru': 0.5, 'heike_hotaru': 0.5,
  // 雨を避ける
  'oomurasaki': -1, 'asagimadara': -1, 'namiageha': -1, 'monshiro': -1, 'gifuchou': -1,
  'oniyanma': -1, 'ginyanma': -1, 'akiakane': -1,
  'tobi': -1, 'ootaka': -1, 'inuwashi': -1, 'hayabusa': -1, 'kumataka': -1, 'misago': -1,
  'abura_koumori': -0.7, 'kanahebi': -0.7,
  'tsubame': -0.3,
  'kabutomushi': -0.3, 'nokogiri_kuwagata': -0.3, 'miyama_kuwagata': -0.3, 'ookuwagata': -0.3,
  // 水中の生き物・植物は雨の影響を直接は受けない
};

double _rainOf(Creature c) {
  final v = speciesRain[c.id];
  if (v != null) return v;
  switch (c.type) {
    case CreatureType.bird:
      return -0.5;
    case CreatureType.animal:
      return -0.2;
    default:
      return 0;
  }
}

Set<DayPart> _partsOf(Creature c) {
  final v = speciesParts[c.id];
  if (v != null) return v;
  switch (c.type) {
    case CreatureType.bird:
    case CreatureType.animal:
      return _diurnal;
    default:
      return _all;
  }
}

/// ベイト（小魚）：多いほど、それを追う種が集まる
const Set<String> baitFish = {
  'maiwashi', 'maaji', 'masaba', 'umitanago', // 海
  'oikawa', 'kawamutsu', 'moroko', 'ugui', 'abura_haya', 'motsugo', 'medaka', 'shinai_motsugo', // 川・池
};

/// ベイトを追う捕食者（回遊魚・魚食の鳥・アザラシ）
const Set<String> baitPredators = {
  'buri', 'katsuo', 'kuromaguro', 'suzuki', 'tachiuo', 'hirame', 'magochi', 'kasago', 'namazu', 'nigoi',
  'umineko', 'kamome', 'ooseguro', 'misago', 'oomizunagidori',
  'kawau', 'kawasemi', 'yamasemi', 'aosagi', 'kosagi', 'daisagi', 'goisagi', 'kaitsuburi',
  'zenigata',
};

// ---- 出現率の計算 ---------------------------------------------------------

class Appear {
  final double p; // 出現率 0〜1
  final List<String> why; // 出やすい／出にくい理由
  const Appear(this.p, this.why);

  /// ◎高い ○ふつう △低い ×ほぼ出ない
  String get label => p >= 0.75 ? '高い' : p >= 0.45 ? 'ふつう' : p >= 0.2 ? '低い' : 'ほぼ出ない';
}

bool _adjacent(DayPart a, DayPart b) => ((a.index - b.index).abs() % 4) == 1 || ((a.index - b.index).abs() % 4) == 3;

double _roll(String key) {
  var h = 2166136261;
  for (final u in key.codeUnits) {
    h ^= u;
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  return (h % 10000) / 10000.0;
}

class ActivityEngine {
  ActivityEngine._();

  static ConservationState? _cState;
  static ActivityContext? _cCtx;
  static final _apCache = <Habitat, Map<String, Appear>>{};
  static final _visCache = <Habitat, List<Creature>>{};

  /// 基本の出現率（植物は動かないので常に見える）
  static double _base(Creature c) => c.type == CreatureType.plant ? 1.0 : 0.7;

  /// そのエリアに暮らす種ごとの出現率と理由
  static Map<String, Appear> appearances(Habitat h, ConservationState state,
      ConservationNotifier notifier, List<Creature> creatures) {
    final x = ActivityContext.current;
    if (!identical(state, _cState) || !identical(x, _cCtx)) {
      _cState = state;
      _cCtx = x;
      _apCache.clear();
      _visCache.clear();
    }
    return _apCache.putIfAbsent(h, () => _compute(h, state, notifier, creatures, x));
  }

  static Map<String, Appear> _compute(Habitat h, ConservationState state,
      ConservationNotifier notifier, List<Creature> creatures, ActivityContext x) {
    final living = [
      for (final c in creatures)
        if (notifier.lives(c, h, s: state)) c,
    ];
    final out = <String, Appear>{};

    Appear own(Creature c) {
      var p = _base(c);
      final why = <String>[];

      // 時間帯
      final parts = _partsOf(c);
      if (parts.length < 4) {
        if (parts.contains(x.part)) {
          p *= 1.0;
          why.add('${x.part.label}は活動する時間');
        } else if (parts.length <= 2 && parts.any((q) => _adjacent(q, x.part))) {
          p *= 0.5; // 活動時間の前後は少し見られる
          why.add('${x.part.label}は活動が鈍る');
        } else if (parts.length >= 3) {
          p *= 0.08; // 昼行性は夜、夜行性は昼にほとんど出ない
          why.add('${x.part.label}はほとんど活動しない');
        } else {
          p *= 0.05;
          why.add('${x.part.label}はほとんど活動しない');
        }
      }

      // 雨への反応
      final a = _rainOf(c);
      if (x.hasWeather && a != 0) {
        final wet = x.pourOf(h) ? 1.0 : x.wetOf(h);
        double m;
        if (a > 0) {
          m = (1 - a * 0.6) + a * 0.6 * wet; // 乾いていると隠れ、雨のあとに出る
          if (wet >= 0.5) why.add('雨のあとで活発');
          if (wet < 0.2) why.add('乾いていて隠れている');
        } else {
          final k = -a;
          m = x.pourOf(h) ? 1 - 0.9 * k : 1 - 0.3 * k * wet;
          if (x.pourOf(h)) why.add('雨で姿を隠す');
        }
        p *= m;
      }

      // 山の雨 → 川の魚が動く
      if (h == Habitat.river && c.type == CreatureType.fish && x.hasWeather) {
        final up = x.upstreamWet;
        p *= 0.8 + 0.6 * up;
        if (up >= 0.5) why.add('山の雨で川が動き、魚が動きやすい');
        if (x.pourOf(h)) {
          p *= 0.75;
          why.add('増水で魚が潜る');
        }
      }
      // 川からの栄養 → 海のベイトが寄る
      if (h == Habitat.ocean && baitFish.contains(c.id) && x.hasWeather) {
        final rv = x.wetOf(Habitat.river);
        p *= 0.8 + 0.6 * rv;
        if (rv >= 0.5) why.add('川から栄養が流れ込み、ベイトが集まる');
      }
      // 海が荒れると見えにくい
      if (h == Habitat.ocean && c.type != CreatureType.plant && x.windOf(h) >= 8) {
        p *= 0.7;
        why.add('海が荒れていて見えにくい');
      }
      return Appear(p.clamp(0.0, 1.0).toDouble(), why);
    }

    // 1) 捕食者以外
    for (final c in living) {
      if (!baitPredators.contains(c.id)) out[c.id] = own(c);
    }
    // 2) ベイトの多さ → 捕食者
    final baits = [for (final c in living) if (baitFish.contains(c.id)) out[c.id]!.p];
    final idx = baits.isEmpty ? 0.8 : (baits.reduce((a, b) => a + b) / baits.length / 0.7).clamp(0.0, 1.4);
    for (final c in living) {
      if (!baitPredators.contains(c.id)) continue;
      final o = own(c);
      final m = 0.45 + 0.7 * idx;
      final why = [...o.why];
      if (idx >= 1.0) why.add('ベイト(小魚)が多く、追って集まる');
      if (idx < 0.7) why.add('ベイト(小魚)が少なく、寄りつきにくい');
      out[c.id] = Appear((o.p * m).clamp(0.0, 1.0).toDouble(), why);
    }
    return out;
  }

  /// いま実際に姿を見せる種（出現率でくじを引き、同じ時間帯のあいだは固定）。種類ごとに上限をかける
  static List<Creature> visible(Habitat h, ConservationState state,
      ConservationNotifier notifier, List<Creature> creatures, Map<CreatureType, int> limit) {
    final ap = appearances(h, state, notifier, creatures);
    final cached = _visCache[h];
    if (cached != null) return cached;
    final x = ActivityContext.current;
    final day = '${x.time.year}${x.time.month}${x.time.day}';
    final bucket = x.manual ? 'p${x.part.index}' : '${x.time.hour}';
    final scored = <(Creature, double)>[
      for (final c in creatures)
        if (ap.containsKey(c.id) && _roll('${c.id}|$day|$bucket|${h.index}') < ap[c.id]!.p)
          (c, notifier.suitability(c, h, s: state) * (0.5 + 0.5 * ap[c.id]!.p)),
    ];
    scored.sort((a, b) {
      final d = b.$2.compareTo(a.$2);
      return d != 0 ? d : a.$1.id.compareTo(b.$1.id);
    });
    final count = <CreatureType, int>{};
    final res = <Creature>[];
    for (final (c, _) in scored) {
      final n = count[c.type] ?? 0;
      if (n >= (limit[c.type] ?? 3)) continue;
      count[c.type] = n + 1;
      res.add(c);
    }
    return _visCache[h] = res;
  }
}
