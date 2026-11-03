import 'package:flutter/material.dart';

/// 季節ごとに起こる出来事。1季節前に「予報」として表示され、備えることができる。
class SeasonEvent {
  final String id;
  final String title;
  final IconData icon;
  final String forecast; // 予報（備えのヒント付き）
  final String result; // 発生後の説明
  final List<int> seasons; // 0=春 1=夏 2=秋 3=冬
  final int weight;
  final bool positive;

  const SeasonEvent({
    required this.id,
    required this.title,
    required this.icon,
    required this.forecast,
    required this.result,
    required this.seasons,
    required this.weight,
    this.positive = false,
  });
}

const seasonEvents = <SeasonEvent>[
  SeasonEvent(
    id: 'typhoon',
    title: '台風',
    icon: Icons.cyclone,
    forecast: '台風が接近中。川は増水し、森は倒木、海は荒れます。保護区は汚染の流入が少なくなります。',
    result: '台風が通過した。川は増水し、森では倒木が出て、沿岸に汚れが流れ込んだ。',
    seasons: [1, 2],
    weight: 3,
  ),
  SeasonEvent(
    id: 'flood',
    title: '大雨・洪水',
    icon: Icons.thunderstorm,
    forecast: '大雨の予報。川の流速が上がり、池と川に汚れが流れ込みます。',
    result: '大雨で川が増水した。池と川に土砂と汚れが流れ込んだ。',
    seasons: [0, 1],
    weight: 2,
  ),
  SeasonEvent(
    id: 'heatwave',
    title: '猛暑',
    icon: Icons.wb_sunny,
    forecast: '猛暑になりそう。気温・水温が高くなるので、日陰や水温の管理を。',
    result: '猛暑が続いた。全エリアで気温・水温が大きく上昇した。',
    seasons: [1],
    weight: 2,
  ),
  SeasonEvent(
    id: 'drought',
    title: '干ばつ',
    icon: Icons.landscape,
    forecast: '雨が少ない予報。森の土壌水分と川の流れが減ります。灌漑で備えましょう。',
    result: '雨が降らず、森の土が乾き、川の流れが細くなった。',
    seasons: [1, 2],
    weight: 1,
  ),
  SeasonEvent(
    id: 'coldwave',
    title: '寒波',
    icon: Icons.ac_unit,
    forecast: '強い寒波が来ます。暖かい環境を好む生き物が弱ります。',
    result: '寒波で気温・水温が大きく下がった。',
    seasons: [3],
    weight: 3,
  ),
  SeasonEvent(
    id: 'wildfire',
    title: '山火事',
    icon: Icons.local_fire_department,
    forecast: '森が乾いて山火事の恐れ。土壌水分を上げて備えましょう。',
    result: '山火事が発生した。森の植物が焼け、灰で土が痩せた。',
    seasons: [2, 3],
    weight: 3,
  ),
  SeasonEvent(
    id: 'aoko',
    title: 'アオコの発生',
    icon: Icons.water_drop,
    forecast: '池の栄養が多く水温も高いので、アオコ（藻の大発生）の恐れ。栄養を減らしましょう。',
    result: '池にアオコが大発生し、酸素が不足して魚が弱った。',
    seasons: [1],
    weight: 4,
  ),
  SeasonEvent(
    id: 'redtide',
    title: '赤潮',
    icon: Icons.waves,
    forecast: '海の栄養が多く水温も高いため、赤潮の恐れ。栄養と汚染を減らしましょう。',
    result: '赤潮が発生し、海の魚が大きく数を減らした。',
    seasons: [1, 2],
    weight: 4,
  ),
  SeasonEvent(
    id: 'migrants',
    title: '渡り鳥の飛来',
    icon: Icons.flutter_dash,
    forecast: '渡り鳥の群れが近づいています。餌が豊かだと定着します。',
    result: '渡り鳥が飛来し、鳥たちが増えた。',
    seasons: [0, 2],
    weight: 3,
    positive: true,
  ),
  SeasonEvent(
    id: 'invasive',
    title: '外来種の侵入',
    icon: Icons.pest_control,
    forecast: '外来種が持ち込まれる恐れ。',
    result: '外来種のブルーギルが池や川で増えた。在来の魚が圧迫される。',
    seasons: [0, 1, 2, 3],
    weight: 1,
  ),
  SeasonEvent(
    id: 'dumping',
    title: '不法投棄',
    icon: Icons.delete_outline,
    forecast: '不法投棄が増える恐れ。障害物を減らしておくと汚染が溜まりにくくなります。',
    result: '不法投棄があり、どこかのエリアに障害物と汚れが増えた。',
    seasons: [0, 1, 2, 3],
    weight: 2,
  ),
  SeasonEvent(
    id: 'donation',
    title: '保全への寄付',
    icon: Icons.volunteer_activism,
    forecast: '保全活動への寄付が集まりそうです。',
    result: '寄付が集まり、予算が増えた。',
    seasons: [0, 1, 2, 3],
    weight: 1,
    positive: true,
  ),
];

SeasonEvent? findSeasonEvent(String? id) {
  for (final e in seasonEvents) {
    if (e.id == id) return e;
  }
  return null;
}
