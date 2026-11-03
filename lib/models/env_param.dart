/// 環境パラメータ（土壌・水・気候など）。エリアごとに調整できる項目は異なる。
enum EnvParam {
  ph('土壌・水のpH', '', 4, 9, 0.5, 10),
  moisture('土壌水分・水位', '%', 0, 100, 10, 10),
  nutrients('栄養塩（肥沃度）', '%', 0, 100, 10, 8),
  temperature('気温・水温', '℃', 0, 35, 2, 8),
  sunlight('日照', '%', 0, 100, 10, 8),
  salinity('塩分', '%', 0, 100, 10, 12),
  oxygen('溶存酸素', '%', 0, 100, 10, 10),
  flow('流速・潮流', '%', 0, 100, 10, 10),
  elevation('標高', 'm', 0, 3000, 300, 0),
  pollution('汚染度', '%', 0, 100, 10, 15);

  final String label;
  final String unit;
  final double min;
  final double max;
  final double step;
  final int cost;

  const EnvParam(this.label, this.unit, this.min, this.max, this.step, this.cost);

  /// 適正範囲を外れたとき、適合度が 0 になるまでの距離
  double get tolerance => (max - min) * 0.2;

  String get actionUp {
    switch (this) {
      case EnvParam.ph: return '石灰を撒く';
      case EnvParam.moisture: return '灌漑する';
      case EnvParam.nutrients: return '施肥する';
      case EnvParam.temperature: return '温める';
      case EnvParam.sunlight: return '間伐する';
      case EnvParam.salinity: return '海水を導入';
      case EnvParam.oxygen: return '曝気する（酸素を送る）';
      case EnvParam.flow: return '水路を広げる（流れを強める）';
      case EnvParam.elevation: return '';
      case EnvParam.pollution: return '';
    }
  }

  String get actionDown {
    switch (this) {
      case EnvParam.ph: return '酸性化させる';
      case EnvParam.moisture: return '排水する';
      case EnvParam.nutrients: return '栄養を除去';
      case EnvParam.temperature: return '冷やす（日陰）';
      case EnvParam.sunlight: return '遮光する';
      case EnvParam.salinity: return '淡水を導入';
      case EnvParam.oxygen: return '曝気をやめる';
      case EnvParam.flow: return '堰を設ける（流れを弱める）';
      case EnvParam.elevation: return '';
      case EnvParam.pollution: return '浄化する';
    }
  }

  String format(double v) =>
      this == EnvParam.ph ? v.toStringAsFixed(1) : '${v.round()}$unit';
}
