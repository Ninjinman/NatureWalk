import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/season_events.dart';
import '../data/species_database.dart';
import '../data/species_range.dart';
import '../data/species_traits.dart';
import '../models/creature.dart';
import '../models/env_param.dart';
import '../services/real_weather.dart';

extension HabitatLabel on Habitat {
  String get label {
    switch (this) {
      case Habitat.forest: return '森';
      case Habitat.pond: return '池';
      case Habitat.river: return '川';
      case Habitat.ocean: return '海';
      case Habitat.mountainLow: return '山（低）';
      case Habitat.mountainMid: return '山（中）';
      case Habitat.mountainHigh: return '山（高）';
    }
  }

  String get obstacleName {
    switch (this) {
      case Habitat.forest: return '倒木・岩';
      case Habitat.pond: return '流木・ゴミ';
      case Habitat.river: return '堰き止める岩・流木';
      case Habitat.ocean: return '漂着ゴミ・岩礁';
      case Habitat.mountainLow:
      case Habitat.mountainMid:
      case Habitat.mountainHigh:
        return '落石・倒木';
    }
  }

  /// このエリアでプレイヤーが調整できるパラメータ（エリアごとに異なる）
  List<EnvParam> get params {
    switch (this) {
      case Habitat.forest:
        return [EnvParam.ph, EnvParam.moisture, EnvParam.nutrients,
            EnvParam.temperature, EnvParam.sunlight, EnvParam.pollution];
      case Habitat.pond:
        return [EnvParam.ph, EnvParam.oxygen, EnvParam.nutrients,
            EnvParam.temperature, EnvParam.sunlight, EnvParam.pollution];
      case Habitat.river:
        return [EnvParam.ph, EnvParam.flow, EnvParam.oxygen,
            EnvParam.temperature, EnvParam.sunlight, EnvParam.pollution];
      case Habitat.ocean:
        return [EnvParam.ph, EnvParam.salinity, EnvParam.flow,
            EnvParam.temperature, EnvParam.nutrients, EnvParam.pollution];
      case Habitat.mountainLow:
      case Habitat.mountainMid:
      case Habitat.mountainHigh:
        // 気温は標高で決まる（標高は開始時に設定）
        return [EnvParam.ph, EnvParam.moisture, EnvParam.nutrients,
            EnvParam.sunlight, EnvParam.pollution];
    }
  }
}

/// 1つのエリアの環境（複数パラメータ）。調整対象外のパラメータは固定値。
class AreaEnv {
  final Map<EnvParam, double> values;
  final bool protectedArea;

  /// 流れ・日照をさえぎる障害物（倒木・岩・ゴミなど）の数。多いほど汚染が溜まりやすい
  final int obstacles;

  const AreaEnv(this.values, {this.protectedArea = false, this.obstacles = 3});

  double operator [](EnvParam p) => values[p]!;

  AreaEnv with_(EnvParam p, double v) => AreaEnv(
        {...values, p: v.clamp(p.min, p.max).toDouble()},
        protectedArea: protectedArea,
        obstacles: obstacles,
      );

  AreaEnv copyWith({bool? protectedArea, int? obstacles}) => AreaEnv(
        values,
        protectedArea: protectedArea ?? this.protectedArea,
        obstacles: obstacles ?? this.obstacles,
      );

  static const _defaults = {
    EnvParam.ph: 7.0,
    EnvParam.moisture: 100.0,
    EnvParam.nutrients: 40.0,
    EnvParam.temperature: 15.0,
    EnvParam.sunlight: 60.0,
    EnvParam.salinity: 0.0,
    EnvParam.oxygen: 90.0,
    EnvParam.flow: 0.0,
    EnvParam.elevation: 0.0,
    EnvParam.pollution: 20.0,
  };

  static AreaEnv _make(Map<EnvParam, double> m) =>
      AreaEnv({for (final p in EnvParam.values) p: m[p] ?? _defaults[p]!});

  static AreaEnv initial(Habitat h) {
    switch (h) {
      case Habitat.forest:
        return _make({
          EnvParam.ph: 6, EnvParam.moisture: 55, EnvParam.nutrients: 50,
          EnvParam.temperature: 15, EnvParam.sunlight: 55, EnvParam.pollution: 20,
        });
      case Habitat.pond:
        return _make({
          EnvParam.ph: 7, EnvParam.moisture: 95, EnvParam.nutrients: 55,
          EnvParam.temperature: 18, EnvParam.sunlight: 60, EnvParam.oxygen: 70,
          EnvParam.flow: 5, EnvParam.pollution: 25,
        });
      case Habitat.river:
        return _make({
          EnvParam.ph: 7, EnvParam.moisture: 95, EnvParam.nutrients: 35,
          EnvParam.temperature: 13, EnvParam.sunlight: 50, EnvParam.oxygen: 85,
          EnvParam.flow: 55, EnvParam.pollution: 20,
        });
      case Habitat.ocean:
        return _make({
          EnvParam.ph: 8.1, EnvParam.moisture: 100, EnvParam.nutrients: 30,
          EnvParam.temperature: 22, EnvParam.sunlight: 70, EnvParam.salinity: 90,
          EnvParam.oxygen: 90, EnvParam.flow: 40, EnvParam.pollution: 25,
        });
      case Habitat.mountainLow:
        return _make({
          EnvParam.ph: 6.0, EnvParam.moisture: 60, EnvParam.nutrients: 50,
          EnvParam.temperature: tempForElevation(500), EnvParam.sunlight: 55,
          EnvParam.elevation: 500, EnvParam.oxygen: 95, EnvParam.flow: 50, EnvParam.pollution: 15,
        });
      case Habitat.mountainMid:
        return _make({
          EnvParam.ph: 5.7, EnvParam.moisture: 60, EnvParam.nutrients: 40,
          EnvParam.temperature: tempForElevation(1500), EnvParam.sunlight: 62,
          EnvParam.elevation: 1500, EnvParam.oxygen: 95, EnvParam.flow: 60, EnvParam.pollution: 10,
        });
      case Habitat.mountainHigh:
        return _make({
          EnvParam.ph: 5.4, EnvParam.moisture: 45, EnvParam.nutrients: 25,
          EnvParam.temperature: tempForElevation(2500), EnvParam.sunlight: 78,
          EnvParam.elevation: 2500, EnvParam.oxygen: 95, EnvParam.flow: 55, EnvParam.pollution: 5,
        });
    }
  }

  /// 標高による気温（海面で17℃、100mごとに0.65℃低下）
  static double tempForElevation(double m) => (17 - 0.0065 * m).clamp(0.0, 35.0).toDouble();
}

class ConservationState {
  static const int maxTurns = 24; // 6年分（1ターン=1季節）
  static const List<double> seasonTempOffset = [0, 8, 0, -8]; // 春夏秋冬

  final int turn;
  final int budget;
  final Map<Habitat, AreaEnv> areas;
  final Map<String, int> population;
  final List<String> log;

  /// 次の季節に起こる予定の出来事（予報）。null なら平穏
  final String? pendingEvent;

  /// 直前の季節に起きた出来事
  final String? lastEvent;

  /// この季節だけの気温補正（猛暑・寒波）
  final double tempShift;

  /// 現実の天気とリンクした設定
  final int startSeason; // ゲーム開始時の季節（現実の月から決める）
  final Map<Habitat, double> weatherShifts; // 場所ごとの、現実の気温の補正
  final Map<Habitat, double> flowTargets; // 現実の潮流・川の流量から決めた流速の目標
  final String? weatherNote; // 予報が現実の天気に基づく場合の説明
  final bool weatherLinked;
  final bool pendingFromReal;

  /// 参考にしている現実の場所（分布の判定用。開始前に決まる）
  final Map<Habitat, String> regions;
  final Map<Habitat, String> placeNames;

  /// この場所の分布に含まれない種（その地域には生息しない）
  final Set<String> absent;

  /// 図鑑に登録された（実際に姿を見かけた）種。やり直しても引き継ぐ
  final Set<String> discovered;

  /// 今回のプレイで出会った種（目標：場所や条件を試して、どれだけ多くの種に出会えるか）
  final Set<String> foundNow;

  /// プレイ開始時点の図鑑の数（今回新しく載った数を数えるため）
  final int dexAtStart;

  /// 未発見の種についての予想メモ
  final Map<String, String> memos;

  const ConservationState({
    required this.turn,
    required this.budget,
    required this.areas,
    required this.population,
    required this.log,
    this.pendingEvent,
    this.lastEvent,
    this.tempShift = 0,
    this.startSeason = 0,
    this.weatherShifts = const {},
    this.flowTargets = const {},
    this.weatherNote,
    this.weatherLinked = false,
    this.pendingFromReal = false,
    this.regions = const {},
    this.placeNames = const {},
    this.absent = const {},
    this.discovered = const {},
    this.foundNow = const {},
    this.dexAtStart = 0,
    this.memos = const {},
  });

  bool get finished => turn >= maxTurns;
  int get season => (startSeason + turn) % 4;
  String get seasonLabel => const ['春', '夏', '秋', '冬'][season];
  int get year => min(turn ~/ 4 + 1, maxTurns ~/ 4);
  int get aliveCount => population.values.where((p) => p > 0).length;

  /// この場所で出会いうる種の数（分布外を除く）
  int get total => SpeciesDatabase.instance.all.length - absent.length;

  /// 図鑑に載っている全種の数
  int get dexTotal => SpeciesDatabase.instance.all.length;

  ConservationState copyWith({
    int? turn,
    int? budget,
    Map<Habitat, AreaEnv>? areas,
    Map<String, int>? population,
    List<String>? log,
    double? tempShift,
    Map<Habitat, double>? weatherShifts,
    Map<Habitat, double>? flowTargets,
    Map<Habitat, String>? regions,
    Map<Habitat, String>? placeNames,
    Set<String>? absent,
    Set<String>? discovered,
    Set<String>? foundNow,
    int? dexAtStart,
    Map<String, String>? memos,
  }) =>
      ConservationState(
        turn: turn ?? this.turn,
        budget: budget ?? this.budget,
        areas: areas ?? this.areas,
        population: population ?? this.population,
        log: log ?? this.log,
        pendingEvent: pendingEvent,
        lastEvent: lastEvent,
        tempShift: tempShift ?? this.tempShift,
        startSeason: startSeason,
        weatherShifts: weatherShifts ?? this.weatherShifts,
        flowTargets: flowTargets ?? this.flowTargets,
        weatherNote: weatherNote,
        weatherLinked: weatherLinked,
        pendingFromReal: pendingFromReal,
        regions: regions ?? this.regions,
        placeNames: placeNames ?? this.placeNames,
        absent: absent ?? this.absent,
        discovered: discovered ?? this.discovered,
        foundNow: foundNow ?? this.foundNow,
        dexAtStart: dexAtStart ?? this.dexAtStart,
        memos: memos ?? this.memos,
      );
}

/// 種×エリアの適合度（0〜1）
double paramFactor(double v, Range r, EnvParam p) {
  final (lo, hi) = r;
  final d = v < lo ? lo - v : (v > hi ? v - hi : 0.0);
  return max(0.0, 1 - d / p.tolerance);
}

class ConservationNotifier extends Notifier<ConservationState> {
  final _rand = Random();

  // main() で初期化済みのDBを直接参照する（Providerの非同期読み込みを待たない）
  List<Creature> get _creatures => SpeciesDatabase.instance.all;

  @override
  ConservationState build() => _initial();

  Map<Habitat, RealWeather> _lastInfo = {};

  /// 現実の情報から、気温補正・流速の目標・最初の予報を決める
  ({int season, Map<Habitat, double> shifts, Map<Habitat, double> flows, EventCandidate? event}) _fromInfo(
      Map<Habitat, RealWeather> info) {
    final shifts = {for (final e in info.entries) e.key: e.value.shift};
    final flows = <Habitat, double>{
      for (final e in info.entries)
        if (e.value.flowTarget != null) e.key: e.value.flowTarget!,
    };
    EventCandidate? best;
    for (final w in info.values) {
      for (final c in w.candidates) {
        if (best == null || c.$2 > best.$2) best = c;
      }
    }
    final any = info[Habitat.forest] ?? (info.isEmpty ? null : info.values.first);
    return (season: any?.season ?? 0, shifts: shifts, flows: flows, event: best);
  }

  ConservationState _initial() {
    final areas = {for (final h in Habitat.values) h: AreaEnv.initial(h)};
    final pop = {for (final c in _creatures) c.id: c.rarity <= 1 ? 8 : 0};
    final info = _lastInfo;
    final r = _fromInfo(info);
    final st = ConservationState(
      turn: 0,
      budget: 100,
      areas: areas,
      population: pop,
      log: [
        if (info.isNotEmpty) '現実の天気・環境とリンク',
        '天気と場所に合わせて、生きものが現れる。探して図鑑を埋めよう。',
      ],
      startSeason: r.season,
      weatherShifts: r.shifts,
      flowTargets: r.flows,
      weatherNote: r.event?.$3,
      weatherLinked: info.isNotEmpty,
      pendingEvent: r.event?.$1 ?? _rollEvent(r.season, areas),
      pendingFromReal: r.event != null,
      discovered: {..._discoveredAll},
      dexAtStart: _discoveredAll.length,
      memos: {..._memosAll},
    );
    final pl = _lastPlaces;
    return pl == null ? _autoPopulate(st) : _applyPlacesTo(st, pl);
  }

  Map<Habitat, Place>? _lastPlaces;
  final Set<String> _discoveredAll = {};
  final Map<String, String> _memosAll = {};

  /// 未発見の種についての予想メモ
  void setMemo(String id, String text) {
    final t = text.trim();
    if (t.isEmpty) {
      _memosAll.remove(id);
    } else {
      _memosAll[id] = t;
    }
    state = state.copyWith(memos: {..._memosAll});
  }

  /// 姿を見かけた種を図鑑に登録する
  void markDiscovered(Iterable<String> ids) {
    // 今回のプレイで初めて出会った種（図鑑に載っていても数える）
    final now = ids.where((id) => !state.foundNow.contains(id)).toSet();
    if (now.isEmpty) return;
    // 図鑑に初めて載る種だけ、新発見のボーナス
    final add = now.where((id) => !state.discovered.contains(id)).toSet();
    _discoveredAll.addAll(add);
    // 絶滅危惧種などを見つけたら、ボーナスの予算
    var bonus = 0;
    final logs = <String>[];
    for (final id in add) {
      final c = SpeciesDatabase.instance.findById(id);
      if (c != null && c.discoveryBonus > 0) {
        bonus += c.discoveryBonus;
        logs.add('${c.redLabel}の${c.nameJa}を発見（予算 +${c.discoveryBonus}）');
      }
    }
    state = state.copyWith(
      discovered: {...state.discovered, ...add},
      foundNow: {...state.foundNow, ...now},
      budget: state.budget + bonus,
      log: [...logs, ...state.log].take(30).toList(),
    );
  }

  /// 分布：その場所の地域に、その種が生息するか
  bool inRange(Creature c, Habitat h, {ConservationState? s}) {
    final st = s ?? state;
    final region = st.regions[h];
    if (region == null) return true; // 場所が未設定なら制限しない
    final range = speciesRange[c.id];
    if (range != null && !range.contains(region)) return false;
    final not = speciesNotIn[c.id];
    final name = st.placeNames[h];
    if (not != null && name != null && not.contains(name)) return false;
    return true;
  }

  ConservationState _applyPlacesTo(ConservationState st, Map<Habitat, Place> pl) {
    final tmp = st.copyWith(
      regions: {for (final e in pl.entries) e.key: e.value.region},
      placeNames: {for (final e in pl.entries) e.key: e.value.name},
    );
    final absent = <String>{};
    for (final c in _creatures) {
      if (!c.habitats.any((h) => inRange(c, h, s: tmp))) absent.add(c.id);
    }
    final pop = {...st.population};
    for (final c in _creatures) {
      pop[c.id] = absent.contains(c.id) ? 0 : (st.turn == 0 ? (c.rarity <= 1 ? 8 : 0) : (pop[c.id] ?? 0));
    }
    return _autoPopulate(tmp.copyWith(absent: absent, population: pop));
  }

  /// 場所・標高・季節・天気に合う種が、自然に生息する（個体数は「合うか／合わないか」だけで決まる）
  ConservationState _autoPopulate(ConservationState st) {
    final pop = <String, int>{};
    for (final c in _creatures) {
      var here = false;
      if (!st.absent.contains(c.id)) {
        final seasons = speciesSeasons[c.id];
        final seasonOk = seasons == null || seasons.contains(st.season);
        here = seasonOk && best(c, s: st).$2 >= 0.6;
      }
      pop[c.id] = here ? 20 : 0;
    }
    return st.copyWith(population: pop);
  }

  /// 参考にする現実の場所を設定する。分布（どの種がいるか）は、開始前にだけ決まる
  void setPlaces(Map<Habitat, Place> pl) {
    _lastPlaces = pl;
    if (state.turn != 0) return;
    state = _applyPlacesTo(state, pl);
  }

  /// 現実の情報を反映する（開始前なら季節と最初の予報も現実に合わせる）
  void applyRealInfo(Map<Habitat, RealWeather> info) {
    _lastInfo = info;
    final r = _fromInfo(info);
    if (state.turn == 0) {
      state = ConservationState(
        turn: 0,
        budget: state.budget,
        areas: state.areas,
        population: state.population,
        log: state.weatherLinked ? state.log : ['現実の天気・環境とリンク', ...state.log].take(30).toList(),
        startSeason: r.season,
        weatherShifts: r.shifts,
        flowTargets: r.flows,
        weatherNote: r.event?.$3,
        weatherLinked: true,
        pendingEvent: r.event?.$1 ?? _rollEvent(r.season, state.areas),
        pendingFromReal: r.event != null,
        regions: state.regions,
        placeNames: state.placeNames,
        absent: state.absent,
        discovered: state.discovered,
        foundNow: state.foundNow,
        dexAtStart: state.dexAtStart,
        memos: state.memos,
      );
    } else {
      state = state.copyWith(weatherShifts: r.shifts, flowTargets: r.flows);
    }
    state = _autoPopulate(state);
  }

  /// 山のステージの標高を設定する（開始前だけ。ステージごとの範囲内。気温は標高で決まる）
  void setElevation(Habitat h, double m) {
    if (state.turn != 0 || !h.isMountain) return;
    final (lo, hi) = h.elevationBand;
    final v = m.clamp(lo, hi).toDouble();
    final a = state.areas[h]!;
    final area = a.with_(EnvParam.elevation, v).with_(EnvParam.temperature, AreaEnv.tempForElevation(v));
    _log('${h.label}の標高を ${v.round()}m に設定した', areas: {...state.areas, h: area});
    state = _autoPopulate(state);
  }

  void restart() => state = _initial();

  /// 季節による気温補正（水域は変化が小さい）＋ 猛暑・寒波
  double _seasonTemp(ConservationState st, Habitat h, AreaEnv a, int season) {
    final off = ConservationState.seasonTempOffset[season];
    final land = h.isLand;
    return a[EnvParam.temperature] +
        (land ? off : off / 2) +
        st.tempShift +
        (st.weatherShifts[h] ?? 0) * (land ? 1 : 0.5);
  }

  /// 指定エリアでの種の適合度（1.0=最適）
  double suitability(Creature c, Habitat h,
      {ConservationState? s, Map<Habitat, AreaEnv>? areas, int? season}) {
    final st = s ?? state;
    if (!inRange(c, h, s: st)) return 0.0; // その地域には生息しない
    final a = (areas ?? st.areas)[h]!;
    final traits = speciesTraits[c.id];
    if (traits == null) return 0.5;
    final factors = <double>[];
    traits.ranges.forEach((p, r) {
      final v = p == EnvParam.temperature
          ? _seasonTemp(st, h, a, season ?? st.season)
          : a[p];
      factors.add(paramFactor(v, r, p));
    });
    var score = 0.5 * (factors.reduce((x, y) => x + y) / factors.length) +
        0.5 * factors.reduce(min);

    // 鳥は餌（同じ環境の動植物）の豊富さに依存
    if (c.type == CreatureType.bird) {
      final prey = _creatures
          .where((o) => o.type != CreatureType.bird && o.habitats.contains(h));
      if (prey.isNotEmpty) {
        final alive = prey.where((o) => (st.population[o.id] ?? 0) > 0).length;
        score *= 0.5 + 0.5 * alive / prey.length;
      }
    }
    // 動物は植物（餌・すみか）の豊富さに依存
    if (c.type == CreatureType.animal) {
      final food = _creatures.where((o) => o.type == CreatureType.plant && o.habitats.contains(h));
      if (food.isNotEmpty) {
        final alive = food.where((o) => (st.population[o.id] ?? 0) > 0).length;
        score *= 0.5 + 0.5 * alive / food.length;
      }
    }
    // 外来種ブルーギルが増えると在来魚が圧迫される
    if (c.type == CreatureType.fish &&
        c.id != 'bluegill' &&
        (h == Habitat.pond || h == Habitat.river) &&
        (st.population['bluegill'] ?? 0) >= 30) {
      score *= 0.8;
    }
    return score;
  }

  /// その種が、そのフィールドで暮らしているか（分布内で、適合度がある程度ある）
  bool lives(Creature c, Habitat h, {ConservationState? s}) {
    final st = s ?? state;
    if ((st.population[c.id] ?? 0) <= 0 || !c.habitats.contains(h)) return false;
    return suitability(c, h, s: st) >= 0.4;
  }

  /// 最も適したエリアと適合度
  (Habitat, double) best(Creature c,
      {ConservationState? s, Map<Habitat, AreaEnv>? areas, int? season}) {
    Habitat bh = c.habitats.first;
    double bs = -1;
    for (final h in c.habitats) {
      final v = suitability(c, h, s: s, areas: areas, season: season);
      if (v > bs) {
        bs = v;
        bh = h;
      }
    }
    return (bh, bs);
  }

  /// いま弱っている種の原因を集計して、おすすめの操作を返す（診断）
  List<AreaHint> diagnose(Habitat h) {
    final st = state;
    final a = st.areas[h]!;
    final w = <String, double>{};
    final cnt = <String, int>{};
    final key = <String, (EnvParam, int)>{};
    for (final c in _creatures) {
      if (!lives(c, h, s: st)) continue;
      final tr = speciesTraits[c.id];
      if (tr == null) continue;
      tr.ranges.forEach((p, r) {
        if (!h.params.contains(p)) return;
        final v = p == EnvParam.temperature ? _seasonTemp(st, h, a, st.season) : a[p];
        var dir = 0;
        var d = 0.0;
        if (v < r.$1) {
          dir = 1;
          d = (r.$1 - v) / p.tolerance;
        } else if (v > r.$2) {
          dir = -1;
          d = (v - r.$2) / p.tolerance;
        }
        if (p == EnvParam.pollution && dir > 0) dir = 0;
        if (dir == 0 || d < 0.15) return;
        final k = '${p.index}:$dir';
        key[k] = (p, dir);
        w[k] = (w[k] ?? 0) + min(d, 1.0);
        cnt[k] = (cnt[k] ?? 0) + 1;
      });
    }
    final keys = w.keys.toList()..sort((x, y) => w[y]!.compareTo(w[x]!));
    return [
      for (final k in keys.take(3))
        AreaHint(key[k]!.$1, key[k]!.$2, cnt[k]!),
    ];
  }

  bool _canSpend(int cost) => !state.finished && state.budget >= cost;

  void _log(String msg, {Map<Habitat, AreaEnv>? areas, int spend = 0}) {
    state = state.copyWith(
      budget: state.budget - spend,
      areas: areas,
      log: [msg, ...state.log].take(30).toList(),
    );
  }

  /// パラメータを1ステップ増減する（direction: +1 / -1）
  void adjust(Habitat h, EnvParam p, int direction) {
    if (!h.params.contains(p)) return; // そのエリアで調整できない項目
    final cost = p.cost;
    if (!_canSpend(cost)) return;
    final a = state.areas[h]!;
    // 汚染は浄化のみ可能
    if (p == EnvParam.pollution && direction > 0) return;
    final next = a[p] + direction * p.step;
    if (next < p.min - 1e-9 || next > p.max + 1e-9) return;
    final label = direction > 0 ? p.actionUp : p.actionDown;
    final area = (p == EnvParam.pollution) ? a.with_(p, a[p] - 15) : a.with_(p, next);
    _log('${h.label}：$label（${p.label} → ${p.format(area[p])}）',
        areas: {...state.areas, h: area}, spend: cost);
  }

  static const int removeObstacleCost = 10;

  /// 障害物を1つ撤去する（汚染の流入が減る）
  void removeObstacle(Habitat h) {
    final a = state.areas[h]!;
    if (a.obstacles <= 0 || !_canSpend(removeObstacleCost)) return;
    _log('${h.label}の${h.obstacleName}を撤去した',
        areas: {...state.areas, h: a.copyWith(obstacles: a.obstacles - 1)},
        spend: removeObstacleCost);
  }

  void protect(Habitat h) {
    const cost = 40;
    final a = state.areas[h]!;
    if (a.protectedArea || !_canSpend(cost)) return;
    _log('${h.label}を保護区に指定（汚染の流入を抑制）',
        areas: {...state.areas, h: a.copyWith(protectedArea: true)}, spend: cost);
  }

  int reintroduceCost(Creature c) => 30 + c.rarity * 10;

  /// 絶滅した種を再導入（適合度が十分な場合のみ成功）
  void reintroduce(Creature c) {
    final cost = reintroduceCost(c);
    if (state.absent.contains(c.id) || (state.population[c.id] ?? 0) > 0 || !_canSpend(cost)) return;
    if (best(c).$2 < 0.6) {
      _log('${c.nameJa}の再導入は失敗：環境が合っていません');
      return;
    }
    state = state.copyWith(
      budget: state.budget - cost,
      population: {...state.population, c.id: 5},
      log: ['${c.nameJa}を再導入した', ...state.log].take(30).toList(),
    );
  }

  // ---------------------------------------------------------------------
  // 出来事（予報 → 発生）
  // ---------------------------------------------------------------------

  /// 指定した季節に起こりうる出来事を、環境の状態を見て抽選する（約55%で何か起こる）
  String? _rollEvent(int season, Map<Habitat, AreaEnv> areas) {
    if (_rand.nextDouble() > 0.55) return null;
    bool ok(SeasonEvent e) {
      if (!e.seasons.contains(season)) return false;
      switch (e.id) {
        case 'wildfire':
          return areas[Habitat.forest]![EnvParam.moisture] < 45;
        case 'aoko':
          final p = areas[Habitat.pond]!;
          return p[EnvParam.nutrients] >= 55 && p[EnvParam.temperature] >= 20;
        case 'redtide':
          final o = areas[Habitat.ocean]!;
          return o[EnvParam.nutrients] >= 45 && o[EnvParam.temperature] >= 20;
        default:
          return true;
      }
    }

    final list = seasonEvents.where(ok).toList();
    if (list.isEmpty) return null;
    var pick = _rand.nextInt(list.fold<int>(0, (a, e) => a + e.weight));
    for (final e in list) {
      pick -= e.weight;
      if (pick < 0) return e.id;
    }
    return list.last.id;
  }

  AreaEnv _mod(AreaEnv a, Map<EnvParam, double> delta) {
    var r = a;
    delta.forEach((p, d) {
      // 保護区は汚染の流入が半分になる
      final k = (a.protectedArea && p == EnvParam.pollution && d > 0) ? 0.5 : 1.0;
      r = r.with_(p, r[p] + d * k);
    });
    return r;
  }

  /// 条件に合う生きものの個体数を割合で減らす
  void _cull(Map<String, int> pop, Iterable<Creature> targets, double frac,
      List<String> logs) {
    for (final c in targets) {
      final n = pop[c.id] ?? 0;
      if (n <= 0) continue;
      final left = max(0, n - (n * frac).ceil());
      pop[c.id] = left;
      if (left == 0) logs.add('${c.nameJa}が姿を消しました…');
    }
  }

  /// 出来事を適用する。戻り値は (今季の気温補正, 予算の増減)
  (double, int) _applyEvent(String id, Map<Habitat, AreaEnv> areas,
      Map<String, int> pop, List<String> logs) {
    var shift = 0.0;
    var money = 0;
    final all = _creatures;
    final forestPlants = all.where(
        (c) => c.type == CreatureType.plant && c.habitats.contains(Habitat.forest));

    switch (id) {
      case 'typhoon':
        areas[Habitat.forest] = _mod(areas[Habitat.forest]!,
                {EnvParam.moisture: 25, EnvParam.sunlight: 15, EnvParam.pollution: 5})
            .copyWith(obstacles: areas[Habitat.forest]!.obstacles + 1);
        areas[Habitat.pond] = _mod(areas[Habitat.pond]!,
            {EnvParam.pollution: 10, EnvParam.nutrients: 10});
        areas[Habitat.river] = _mod(
                areas[Habitat.river]!, {EnvParam.flow: 40, EnvParam.pollution: 10})
            .copyWith(obstacles: areas[Habitat.river]!.obstacles + 1);
        areas[Habitat.ocean] = _mod(areas[Habitat.ocean]!,
            {EnvParam.flow: 35, EnvParam.pollution: 10, EnvParam.salinity: -10});
        for (final m in [Habitat.mountainLow, Habitat.mountainMid, Habitat.mountainHigh]) {
          areas[m] = _mod(areas[m]!, {EnvParam.moisture: 20, EnvParam.pollution: 4})
              .copyWith(obstacles: areas[m]!.obstacles + 1);
        }
        if (!areas[Habitat.forest]!.protectedArea) {
          _cull(pop, forestPlants, 0.15, logs);
        }
      case 'flood':
        areas[Habitat.river] = _mod(
            areas[Habitat.river]!, {EnvParam.flow: 30, EnvParam.pollution: 12});
        areas[Habitat.pond] = _mod(
            areas[Habitat.pond]!, {EnvParam.pollution: 12, EnvParam.oxygen: -10});
        areas[Habitat.forest] = _mod(areas[Habitat.forest]!, {EnvParam.moisture: 15});
      case 'heatwave':
        shift = 6;
      case 'coldwave':
        shift = -6;
      case 'drought':
        areas[Habitat.forest] = _mod(areas[Habitat.forest]!, {EnvParam.moisture: -25});
        areas[Habitat.river] = _mod(areas[Habitat.river]!, {EnvParam.flow: -25});
        areas[Habitat.pond] = _mod(areas[Habitat.pond]!, {EnvParam.oxygen: -10});
      case 'wildfire':
        areas[Habitat.forest] = _mod(areas[Habitat.forest]!,
            {EnvParam.sunlight: 20, EnvParam.nutrients: 15, EnvParam.pollution: 15});
        _cull(pop, forestPlants, 0.25, logs);
      case 'aoko':
        areas[Habitat.pond] = _mod(
            areas[Habitat.pond]!, {EnvParam.oxygen: -35, EnvParam.pollution: 10});
      case 'redtide':
        areas[Habitat.ocean] = _mod(areas[Habitat.ocean]!, {EnvParam.pollution: 20});
        _cull(
            pop,
            all.where((c) =>
                c.type == CreatureType.fish && c.habitats.contains(Habitat.ocean)),
            0.3,
            logs);
      case 'migrants':
        final birds = all.where((c) => c.type == CreatureType.bird && !state.absent.contains(c.id)).toList()
          ..shuffle(_rand);
        for (final b in birds.take(4)) {
          final n = pop[b.id] ?? 0;
          if (n > 0) {
            pop[b.id] = min(100, n + 8);
          } else if (best(b, areas: areas).$2 >= 0.6) {
            pop[b.id] = 3; // 環境が合えば絶滅した鳥が戻ってくる
            logs.add('${b.nameJa}が戻ってきました');
          }
        }
      case 'invasive':
        final bg = pop['bluegill'] ?? 0;
        pop['bluegill'] = min(100, bg > 0 ? bg + 20 : 8);
      case 'dumping':
        final h = Habitat.values[_rand.nextInt(Habitat.values.length)];
        areas[h] = _mod(areas[h]!, {EnvParam.pollution: 10})
            .copyWith(obstacles: areas[h]!.obstacles + 2);
        logs.add('${h.label}に不法投棄がありました');
      case 'donation':
        money = 30;
    }
    return (shift, money);
  }

  /// 1季節進める
  void nextTurn() {
    if (state.finished) return;
    final logs = <String>[];
    final areas = {...state.areas};
    final population = {...state.population};
    var budget = state.budget;
    var shift = 0.0;
    SeasonEvent? ev;

    // 1. 予報されていた出来事が起こる
    final pending = state.pendingEvent;
    if (pending != null) {
      ev = findSeasonEvent(pending);
      final (sh, money) = _applyEvent(pending, areas, population, logs);
      shift = sh;
      budget += money;
      if (ev != null) logs.add('【${ev.title}】${ev.result}');
    }

    // 2. 環境の自然変動（エリアごとに動くパラメータが異なる）
    for (final h in Habitat.values) {
      final a = areas[h]!;
      final inflow = ((4 + _rand.nextInt(7)) + a.obstacles * 1.5) *
          (a.protectedArea ? 0.4 : 1.0) *
          (h.isMountain ? (h == Habitat.mountainHigh ? 0.4 : 0.6) : 1.0);
      var next = a.with_(EnvParam.pollution, a[EnvParam.pollution] + inflow);
      next = next.with_(EnvParam.ph,
          a[EnvParam.ph] - 0.05 - (a[EnvParam.pollution] > 50 ? 0.1 : 0)); // 酸性化
      if (h.isLand) {
        next = next.with_(EnvParam.moisture, a[EnvParam.moisture] + _rand.nextInt(7) - 3);
      }
      if (a[EnvParam.pollution] > 40) {
        next = next.with_(EnvParam.nutrients, next[EnvParam.nutrients] + 3); // 富栄養化
      }
      // 流れは自然な水準へ戻ろうとする。川は障害物（堰）で弱まる
      if (!h.isLand) {
        final base = switch (h) {
          Habitat.river => 60.0 - a.obstacles * 8,
          Habitat.pond => 5.0,
          _ => 40.0,
        };
        // 現実の潮流・川の流量があれば、それを目標にする（障害物は川の流れを弱める）
        final real = state.flowTargets[h];
        final target = real == null ? base : (h == Habitat.river ? real - a.obstacles * 8 : real);
        final f = a[EnvParam.flow];
        next = next.with_(EnvParam.flow, f + (target - f) * 0.2 + _rand.nextInt(5) - 2);
      }
      // 酸素：富栄養・高水温・汚染で減り、流れがあると回復する
      if (h == Habitat.pond || h == Habitat.river) {
        final delta = 2 +
            (a[EnvParam.flow] > 40 ? 3 : 0) -
            (a[EnvParam.nutrients] > 60 ? 5 : 0) -
            (a[EnvParam.temperature] > 24 ? 3 : 0) -
            a[EnvParam.pollution] * 0.04;
        next = next.with_(EnvParam.oxygen, a[EnvParam.oxygen] + delta);
      }
      if (next[EnvParam.pollution] >= 80 && a[EnvParam.pollution] < 80) {
        logs.add('警告：${h.label}の汚染が深刻です！');
      }
      areas[h] = next;
    }

    // 3. 個体数の変化（今季の環境で評価。猛暑・寒波もここで効く）
    final tmp = state.copyWith(areas: areas, population: population, tempShift: shift);
    for (final c in _creatures) {
      final pop = population[c.id] ?? 0;
      if (pop == 0) continue;
      final s = best(c, s: tmp).$2;
      if (s >= 0.8) {
        population[c.id] = min(100, pop + (pop * 0.2).ceil() + 1);
      } else if (s < 0.25) {
        final n = max(0, pop - (pop * 0.3).ceil());
        population[c.id] = n;
        if (n == 0) logs.add('${c.nameJa}が姿を消しました…');
      } else if (s < 0.5) {
        final n = max(0, pop - (pop * 0.15).ceil());
        population[c.id] = n;
        if (n == 0) logs.add('${c.nameJa}が姿を消しました…');
      }
    }

    // 条件が合う種が、季節ごとにやって来る（まれな種ほど来にくい）
    final nextSeason = (state.startSeason + state.turn + 1) % 4;
    for (final c in _creatures) {
      if ((population[c.id] ?? 0) > 0 || state.absent.contains(c.id)) continue;
      final seasons = speciesSeasons[c.id];
      if (seasons != null && !seasons.contains(nextSeason)) continue;
      final fit = best(c, s: tmp).$2;
      if (fit < 0.6) continue;
      var pc = const [0.0, 0.5, 0.3, 0.18, 0.1, 0.05][c.rarity.clamp(1, 5)];
      if (c.endangered) pc *= 0.5;
      if (c.type == CreatureType.bird) pc *= 1.3;
      if (c.type == CreatureType.animal) pc *= 0.9;
      if (c.type == CreatureType.plant) pc *= 0.8;
      pc *= 0.5 + 0.5 * fit;
      if (_rand.nextDouble() < pc) {
        population[c.id] = 3;
        logs.add('${c.nameJa}がやって来ました');
      }
    }

    final alive = population.values.where((p) => p > 0).length;
    final turn = state.turn + 1;
    state = ConservationState(
      turn: turn,
      budget: budget + 12 + alive ~/ 2,
      areas: areas,
      population: population,
      log: [...logs.reversed, ...state.log].take(30).toList(),
      pendingEvent: turn >= ConservationState.maxTurns
          ? null
          : _rollEvent((state.startSeason + turn) % 4, areas),
      lastEvent: ev?.id,
      tempShift: 0,
      startSeason: state.startSeason,
      weatherShifts: state.weatherShifts,
      flowTargets: state.flowTargets,
      weatherLinked: state.weatherLinked,
      regions: state.regions,
      placeNames: state.placeNames,
      absent: state.absent,
      discovered: state.discovered,
      foundNow: state.foundNow,
      dexAtStart: state.dexAtStart,
      memos: state.memos,
    );
  }
}

final conservationProvider =
    NotifierProvider<ConservationNotifier, ConservationState>(
        ConservationNotifier.new);


/// 診断の結果：どのパラメータを、どちらへ動かすと、何種が助かるか
class AreaHint {
  final EnvParam param;
  final int direction; // +1=増やす / -1=減らす
  final int count; // 弱っている種の数
  const AreaHint(this.param, this.direction, this.count);

  /// 操作の名前（「石灰を撒く」など）
  String get command => direction > 0 ? param.actionUp : param.actionDown;

  String get text {
    switch (param) {
      case EnvParam.ph:
        return direction > 0 ? '土・水が酸性に傾いています' : '土・水がアルカリ寄りです';
      case EnvParam.moisture:
        return direction > 0 ? '土が乾いています' : '水がたまりすぎています';
      case EnvParam.nutrients:
        return direction > 0 ? '栄養が足りません' : '栄養が多すぎます（富栄養）';
      case EnvParam.temperature:
        return direction > 0 ? '冷えすぎています' : '暑すぎます';
      case EnvParam.sunlight:
        return direction > 0 ? '日が足りません' : '日差しが強すぎます';
      case EnvParam.salinity:
        return direction > 0 ? '塩分が薄すぎます' : '塩分が濃すぎます';
      case EnvParam.oxygen:
        return '酸素が足りません';
      case EnvParam.flow:
        return direction > 0 ? '流れが弱すぎます' : '流れが強すぎます';
      case EnvParam.elevation:
        return direction > 0 ? '標高が低すぎます' : '標高が高すぎます';
      case EnvParam.pollution:
        return '水・土が汚れています';
    }
  }
}
