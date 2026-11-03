import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/creature.dart';

/// 各フィールドが参考にする、現実の場所
class Place {
  final String name;
  final double lat, lon;
  final String region; // 地域（H=北海道 T=東北 K=関東 C=中部 Ki=近畿 S=中国・四国 Q=九州 O=沖縄）。生き物の分布の判定に使う
  final double elevation; // 標高(m)。山では気温の補正に使う
  const Place(this.name, this.lat, this.lon, this.region, [this.elevation = 0]);
}

const placePresets = <Habitat, List<Place>>{
  Habitat.forest: [
    Place('丹沢・西丹沢', 35.45, 139.05, 'K', 600),
    Place('高尾山', 35.625, 139.243, 'K', 599),
    Place('屋久島', 30.34, 130.51, 'Q', 300),
    Place('白神山地', 40.50, 140.10, 'T', 500),
    Place('奥入瀬渓流', 40.55, 140.99, 'T', 400),
  ],
  Habitat.pond: [
    Place('不忍池（東京）', 35.712, 139.771, 'K'),
    Place('京都・庭園の池', 35.026, 135.795, 'Ki'),
    Place('琵琶湖畔', 35.30, 136.10, 'Ki'),
    Place('札幌・円山', 43.05, 141.30, 'H'),
  ],
  Habitat.river: [
    Place('酒匂川（丹沢）', 35.32, 139.15, 'K'),
    Place('多摩川', 35.625, 139.525, 'K'),
    Place('利根川', 36.10, 139.80, 'K'),
    Place('長良川', 35.40, 136.75, 'C'),
    Place('四万十川', 33.00, 132.95, 'S'),
  ],
  Habitat.ocean: [
    Place('相模湾', 35.15, 139.40, 'K'),
    Place('瀬戸内海', 34.30, 133.80, 'S'),
    Place('東京湾', 35.35, 139.80, 'K'),
    Place('沖縄（那覇沖）', 26.20, 127.60, 'O'),
  ],
  Habitat.mountainLow: [
    Place('高尾山', 35.625, 139.243, 'K', 599),
    Place('丹沢・西丹沢', 35.45, 139.05, 'K', 600),
    Place('筑波山', 36.225, 140.107, 'K', 877),
  ],
  Habitat.mountainMid: [
    Place('丹沢・蛭ヶ岳', 35.50, 139.14, 'K', 1673),
    Place('丹沢・大山', 35.43, 139.25, 'K', 1252),
    Place('霧ヶ峰', 36.10, 138.20, 'C', 1925),
  ],
  Habitat.mountainHigh: [
    Place('八ヶ岳・赤岳', 35.97, 138.37, 'C', 2899),
    Place('立山', 36.57, 137.62, 'C', 3015),
    Place('大雪山・旭岳', 43.66, 142.85, 'H', 2291),
    Place('富士山', 35.36, 138.73, 'C', 3776),
  ],
};

/// 各フィールドで選択中の場所
final placeProvider = StateProvider<Map<Habitat, Place>>(
    (ref) => {for (final h in Habitat.values) h: placePresets[h]!.first});

class DayForecast {
  final DateTime date;
  final double maxT, minT, precip, wind, gust;
  final int code;
  const DayForecast(this.date, this.maxT, this.minT, this.precip, this.wind, this.gust, this.code);
}

/// 海の現実の情報（Open-Meteo Marine API）
class MarineInfo {
  final double sst; // 海面水温(℃)
  final double? sstMean; // 直近の平均
  final double wave; // 波高(m)
  final double currentMs; // 海流の速さ(m/s)
  final double dirDeg; // 海流の向き
  const MarineInfo(this.sst, this.sstMean, this.wave, this.currentMs, this.dirDeg);
}

/// 川の現実の情報（Open-Meteo Flood API / GloFAS の河川流量）
class RiverInfo {
  final double now, mean, maxForecast; // m³/s
  const RiverInfo(this.now, this.mean, this.maxForecast);
}

/// 出来事の候補：(出来事ID, 重大度, 理由)
typedef EventCandidate = (String, int, String);

/// 1つのフィールドが参考にする、現実の場所の天気と環境情報
class RealWeather {
  final Habitat habitat;
  final Place place;
  final DateTime time;
  final double temp, mean7, precip, wind, precipPast3;
  final int code;
  final List<DayForecast> days;
  final MarineInfo? marine;
  final RiverInfo? river;

  const RealWeather(this.habitat, this.place, this.time, this.temp, this.mean7, this.precip, this.wind,
      this.precipPast3, this.code, this.days,
      {this.marine, this.river});

  /// 現実の月から決めた季節（0=春 1=夏 2=秋 3=冬）
  int get season {
    final m = time.month;
    if (m >= 3 && m <= 5) return 0;
    if (m >= 6 && m <= 8) return 1;
    if (m >= 9 && m <= 11) return 2;
    return 3;
  }

  /// 直近1週間の平均との差から決めた、ゲーム内の気温補正（±6℃まで）
  double get shift {
    final m = marine;
    if (habitat == Habitat.ocean && m != null && m.sstMean != null) {
      return ((m.sst - m.sstMean!) * 1.0).clamp(-4.0, 4.0).toDouble();
    }
    return ((temp - mean7) * 0.5).clamp(-6.0, 6.0).toDouble();
  }

  String get label => weatherLabel(code);
  IconData get icon => weatherIcon(code);

  String get summary {
    final d = temp - mean7;
    return '${place.name} $label ${temp.round()}℃（直近平均より ${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)}℃）';
  }

  /// 潮流・川の流れ（現実の値から決めた、ゲーム内の流速の目標）
  double? get flowTarget {
    final m = marine;
    if (habitat == Habitat.ocean && m != null) {
      return (m.currentMs / 0.8 * 100).clamp(10.0, 95.0).toDouble();
    }
    final r = river;
    if (habitat == Habitat.river && r != null && r.mean > 0) {
      return (55 * r.now / r.mean).clamp(15.0, 95.0).toDouble();
    }
    return null;
  }

  /// 調整パネルに出す、このフィールド固有の現実の情報
  String? get extraLine {
    final m = marine;
    if (habitat == Habitat.ocean && m != null) {
      return '海面水温 ${m.sst.toStringAsFixed(1)}℃・海流 ${m.currentMs.toStringAsFixed(2)}m/s・波高 ${m.wave.toStringAsFixed(1)}m';
    }
    final r = river;
    if (habitat == Habitat.river && r != null) {
      final ratio = r.mean > 0 ? r.now / r.mean : 1.0;
      return '河川流量 ${r.now.round()}m³/s（平年比 ${ratio.toStringAsFixed(1)}倍）';
    }
    if (habitat.isMountain) {
      return '標高補正の現在気温 ${temp.toStringAsFixed(1)}℃';
    }
    return null;
  }

  /// 数日先までの予報・海・川の情報から、ゲームの出来事に当てはまるものを探す
  List<EventCandidate> get candidates {
    final out = <EventCandidate>[];
    String day(DayForecast d) => '${d.date.month}/${d.date.day}';
    final head = place.name;
    for (final d in days.take(4)) {
      if (d.gust >= 20 && d.precip >= 30) {
        out.add(('typhoon', 5, '$head：${day(d)} に暴風雨（最大瞬間風速 ${d.gust.round()}m/s・雨量 ${d.precip.round()}mm）の予報'));
        break;
      }
    }
    // 池は「管理された水域」なので、川の増水は天気（雨）だけで判断する
    for (final d in days.take(4)) {
      if (d.precip >= 50) {
        out.add(('flood', 4, '$head：${day(d)} に大雨（雨量 ${d.precip.round()}mm）の予報'));
        break;
      }
    }
    final r = river;
    if (habitat == Habitat.river && r != null && r.mean > 0 && r.maxForecast >= 20 && r.maxForecast >= r.mean * 2.0) {
      out.add(('flood', 4, '$head：河川流量が平年の約${(r.maxForecast / r.mean).toStringAsFixed(1)}倍（最大 ${r.maxForecast.round()}m³/s）になる予報'));
    }
    final m = marine;
    if (habitat == Habitat.ocean && m != null && m.sst >= 23.5 && m.wave <= 1.2 && precipPast3 >= 20) {
      out.add(('redtide', 3, '$head：海面水温 ${m.sst.toStringAsFixed(1)}℃・波が穏やかで、直近の雨で栄養が流れ込み、赤潮が出やすい状況（推定）'));
    }
    for (final d in days.take(4)) {
      if (d.maxT >= 35) {
        out.add(('heatwave', 2, '$head：${day(d)} に猛暑日（最高 ${d.maxT.round()}℃）の予報'));
        break;
      }
    }
    final low = place.elevation < 500;
    for (final d in days.take(4)) {
      if (low && (d.minT <= 0 || (d.code >= 71 && d.code <= 77) || d.code == 85 || d.code == 86)) {
        out.add(('coldwave', 2, '$head：${day(d)} に厳しい冷え込み（最低 ${d.minT.round()}℃）の予報'));
        break;
      }
    }
    if (!low && temp - mean7 <= -4) {
      out.add(('coldwave', 2, '$head：直近より${(mean7 - temp).toStringAsFixed(0)}℃以上の急な冷え込み'));
    }
    return out;
  }
}

String weatherLabel(int code) {
  if (code == 0) return '快晴';
  if (code == 1) return '晴れ';
  if (code == 2) return 'くもり時々晴れ';
  if (code == 3) return 'くもり';
  if (code == 45 || code == 48) return '霧';
  if (code >= 51 && code <= 57) return '霧雨';
  if (code >= 61 && code <= 67) return '雨';
  if (code >= 71 && code <= 77) return '雪';
  if (code >= 80 && code <= 82) return 'にわか雨';
  if (code == 85 || code == 86) return 'にわか雪';
  if (code >= 95) return '雷雨';
  return '不明';
}

IconData weatherIcon(int code) {
  if (code <= 1) return Icons.wb_sunny;
  if (code <= 3) return Icons.wb_cloudy;
  if (code == 45 || code == 48) return Icons.foggy;
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return Icons.water_drop;
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) return Icons.ac_unit;
  if (code >= 95) return Icons.thunderstorm;
  return Icons.cloud;
}

Future<Map<String, dynamic>> _getJson(Uri uri) async {
  final res = await http.get(uri).timeout(const Duration(seconds: 10));
  if (res.statusCode != 200) throw Exception('取得に失敗（${res.statusCode}）');
  return json.decode(res.body) as Map<String, dynamic>;
}

double _d(List l, int i) => ((l[i] ?? 0) as num).toDouble();

/// 1つの場所の現実の情報を取得する。海・川は専用のデータも合わせて取得（失敗しても天気だけは返す）
Future<RealWeather> fetchReal(Habitat h, Place p) async {
  const past = 7;
  final j = await _getJson(Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': '${p.lat}',
    'longitude': '${p.lon}',
    if (p.elevation > 0) 'elevation': '${p.elevation}',
    'current': 'temperature_2m,precipitation,weather_code,wind_speed_10m',
    'daily': 'weather_code,temperature_2m_max,temperature_2m_min,temperature_2m_mean,precipitation_sum,wind_speed_10m_max,wind_gusts_10m_max',
    'timezone': 'Asia/Tokyo',
    'past_days': '$past',
    'forecast_days': '4',
    'wind_speed_unit': 'ms',
  }));
  final cur = j['current'] as Map<String, dynamic>;
  final dly = j['daily'] as Map<String, dynamic>;
  final dates = (dly['time'] as List).cast<String>();
  final now = DateTime.parse(cur['time'] as String);
  var todayIdx = dates.indexWhere((s) {
    final t = DateTime.parse(s);
    return t.year == now.year && t.month == now.month && t.day == now.day;
  });
  if (todayIdx < 0) todayIdx = min(past, dates.length - 1);

  double mean = 0;
  var n = 0;
  var rain3 = 0.0;
  for (var i = 0; i < todayIdx; i++) {
    final m = (dly['temperature_2m_mean'] as List)[i];
    if (m != null) {
      mean += (m as num).toDouble();
      n++;
    }
    if (i >= todayIdx - 3) rain3 += _d(dly['precipitation_sum'] as List, i);
  }
  final temp = (cur['temperature_2m'] as num).toDouble();
  mean = n > 0 ? mean / n : temp;

  final days = [
    for (var i = todayIdx; i < dates.length; i++)
      DayForecast(
        DateTime.parse(dates[i]),
        _d(dly['temperature_2m_max'] as List, i),
        _d(dly['temperature_2m_min'] as List, i),
        _d(dly['precipitation_sum'] as List, i),
        _d(dly['wind_speed_10m_max'] as List, i),
        _d(dly['wind_gusts_10m_max'] as List, i),
        ((dly['weather_code'] as List)[i] as num).toInt(),
      ),
  ];

  MarineInfo? marine;
  RiverInfo? river;
  if (h == Habitat.ocean) {
    try {
      final m = await _getJson(Uri.https('marine-api.open-meteo.com', '/v1/marine', {
        'latitude': '${p.lat}',
        'longitude': '${p.lon}',
        'current': 'wave_height,sea_surface_temperature,ocean_current_velocity,ocean_current_direction',
        'hourly': 'sea_surface_temperature',
        'past_days': '$past',
        'forecast_days': '1',
      }));
      final c = m['current'] as Map<String, dynamic>;
      final hs = ((m['hourly'] as Map<String, dynamic>)['sea_surface_temperature'] as List)
          .whereType<num>()
          .map((e) => e.toDouble())
          .toList();
      marine = MarineInfo(
        (c['sea_surface_temperature'] as num).toDouble(),
        hs.isEmpty ? null : hs.reduce((a, b) => a + b) / hs.length,
        ((c['wave_height'] ?? 0) as num).toDouble(),
        ((c['ocean_current_velocity'] ?? 0) as num).toDouble() / 3.6, // km/h → m/s
        ((c['ocean_current_direction'] ?? 0) as num).toDouble(),
      );
    } catch (_) {}
  }
  if (h == Habitat.river) {
    try {
      final f = await _getJson(Uri.https('flood-api.open-meteo.com', '/v1/flood', {
        'latitude': '${p.lat}',
        'longitude': '${p.lon}',
        'daily': 'river_discharge,river_discharge_mean,river_discharge_max',
        'past_days': '3',
        'forecast_days': '7',
      }));
      final dd = f['daily'] as Map<String, dynamic>;
      final ds = (dd['time'] as List).cast<String>();
      var ti = ds.indexWhere((s) => DateTime.parse(s).day == now.day && DateTime.parse(s).month == now.month);
      if (ti < 0) ti = min(3, ds.length - 1);
      final dis = dd['river_discharge'] as List;
      final mean2 = dd['river_discharge_mean'] as List;
      final mx = dd['river_discharge_max'] as List;
      var maxF = 0.0;
      for (var i = ti; i < ds.length; i++) {
        maxF = max(maxF, mx[i] == null ? 0.0 : (mx[i] as num).toDouble());
      }
      river = RiverInfo(_d(dis, ti), _d(mean2, ti), maxF);
    } catch (_) {}
  }

  return RealWeather(h, p, now, temp, mean, (cur['precipitation'] as num).toDouble(),
      (cur['wind_speed_10m'] as num).toDouble(), rain3, (cur['weather_code'] as num).toInt(), days,
      marine: marine, river: river);
}

/// 各フィールドの現実の情報（取得できたものだけ）。場所を変えると取り直す
final realInfoProvider = FutureProvider<Map<Habitat, RealWeather>>((ref) async {
  final places = ref.watch(placeProvider);
  final out = <Habitat, RealWeather>{};
  await Future.wait([
    for (final h in Habitat.values)
      () async {
        try {
          out[h] = await fetchReal(h, places[h]!);
        } catch (_) {}
      }(),
  ]);
  if (out.isEmpty) throw Exception('天気を取得できませんでした');
  return out;
});
