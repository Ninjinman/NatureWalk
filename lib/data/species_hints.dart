import '../models/creature.dart';
import '../models/env_param.dart';
import 'species_range.dart';
import 'species_traits.dart';

/// まだ出会っていない種へのヒント。
/// 名前や細かい数値は出さず、「どんな場所・条件にいそうか」だけを、ふわっと伝える。
/// 実際の生態にもとづくので、ネットで調べて推測する手がかりになる。
String vagueHint(Creature c) {
  final parts = <String>[];

  // 1. どこで（地域 + フィールド）
  final region = _regionPhrase(speciesRange[c.id]);
  final place = _placePhrase(c.habitats);
  final season = _seasonPhrase(speciesSeasons[c.id]);
  parts.add('${region == null ? '' : '$regionの'}$placeで${season == null ? '' : '$seasonに'}見られるらしい。');

  // 2. どんな条件を好むか（1〜2個だけ）
  final cond = _conditionPhrases(c);
  if (cond.isNotEmpty) parts.add('${cond.take(2).join('、')}。');

  // 3. 珍しさ
  if (c.endangered) {
    parts.add('数が減っていて、大切に守られているという話もある。');
  } else if (c.rarity >= 4) {
    parts.add('めったに姿を見せないらしい。');
  } else if (c.rarity <= 1) {
    parts.add('わりと身近にいるらしい。');
  }
  return parts.join('');
}

String _placePhrase(List<Habitat> hs) {
  String one(Habitat h) {
    switch (h) {
      case Habitat.forest: return '里山の森';
      case Habitat.pond: return '池のほとり';
      case Habitat.river: return '川辺';
      case Habitat.ocean: return '海辺';
      case Habitat.mountainLow: return '低い山';
      case Habitat.mountainMid: return '山の中ほど';
      case Habitat.mountainHigh: return '山の高いところ';
    }
  }

  final names = hs.map(one).toSet().toList();
  return names.take(2).join('や');
}

String? _regionPhrase(Set<String>? r) {
  if (r == null || r.length >= 8) return null;
  if (r.length == 1 && r.contains('O')) return '遠い南の島';
  if (r.length == 1 && r.contains('C')) return '中部の山々';
  if (r.every((e) => e == 'H' || e == 'T' || e == 'C')) return '北国や高い山脈';
  if (r.contains('O') && !r.contains('H')) return '暖かい南のほう';
  if (r.contains('H') && !r.contains('Q') && !r.contains('O')) return '北のほう';
  if (!r.contains('H') && !r.contains('O')) return '本州から南';
  return null;
}

String? _seasonPhrase(Set<int>? s) {
  if (s == null) return null;
  if (s.every((e) => e == 0 || e == 1)) return '暖かい季節';
  if (s.every((e) => e == 2 || e == 3)) return '寒い季節';
  return null;
}

List<String> _conditionPhrases(Creature c) {
  final tr = speciesTraits[c.id]?.ranges;
  if (tr == null) return const [];
  final out = <String>[];
  (double, double)? r(EnvParam p) => tr[p];
  final elv = r(EnvParam.elevation);
  if (elv != null && elv.$1 >= 1500) out.add('空気の薄い高地を好む');
  final tmp = r(EnvParam.temperature);
  if (tmp != null && tmp.$2 <= 14) out.add('寒さに強く、暑いと姿を消す');
  if (tmp != null && tmp.$1 >= 15) out.add('暖かさを好む');
  final pol = r(EnvParam.pollution);
  if (pol != null && pol.$2 <= 30) out.add('きれいな環境でないと現れない');
  if (pol != null && pol.$2 >= 80) out.add('多少の汚れには動じない');
  final sal = r(EnvParam.salinity);
  if (sal != null && sal.$1 >= 50) out.add('塩気のある水を好む');
  final flw = r(EnvParam.flow);
  final oxy = r(EnvParam.oxygen);
  if (flw != null && flw.$1 >= 30 && oxy != null && oxy.$1 >= 50) out.add('流れのある、酸素の多い水を好む');
  if (flw != null && flw.$2 <= 25) out.add('流れの緩やかな水を好む');
  final sun = r(EnvParam.sunlight);
  if (sun != null && sun.$1 >= 70) out.add('日当たりのよい場所を好む');
  if (sun != null && sun.$2 <= 50) out.add('木陰のような薄暗さを好む');
  final ph = r(EnvParam.ph);
  if (ph != null && ph.$2 <= 6.2) out.add('やや酸性の土や水が合うらしい');
  if (ph != null && ph.$1 >= 7.5) out.add('弱アルカリ性の水が合うらしい');
  final wet = r(EnvParam.moisture);
  if (wet != null && wet.$2 <= 50 && c.type == CreatureType.plant) out.add('乾いた土地にも育つ');
  return out;
}
