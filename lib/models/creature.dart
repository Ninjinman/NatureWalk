enum CreatureType { plant, bird, fish, animal }

/// フィールド。山は標高の帯ごとに3つのステージに分かれる（育つ生き物が違う）
enum Habitat { forest, pond, river, ocean, mountainLow, mountainMid, mountainHigh }

extension HabitatKind on Habitat {
  bool get isMountain =>
      this == Habitat.mountainLow || this == Habitat.mountainMid || this == Habitat.mountainHigh;

  /// 陸のフィールド（気温の季節変化が大きく、水の流れ・酸素がない）
  bool get isLand => this == Habitat.forest || isMountain;

  /// 山のステージが取れる標高の範囲(m)
  (double, double) get elevationBand {
    switch (this) {
      case Habitat.mountainLow:
        return (200, 1000);
      case Habitat.mountainMid:
        return (1000, 2000);
      case Habitat.mountainHigh:
        return (2000, 3000);
      default:
        return (0, 0);
    }
  }
}

class IdentificationTip {
  final String part;
  final String detail;
  final String? imagePath;

  const IdentificationTip({
    required this.part,
    required this.detail,
    this.imagePath,
  });

  factory IdentificationTip.fromJson(Map<String, dynamic> json) {
    return IdentificationTip(
      part: json['part'] as String,
      detail: json['detail'] as String,
      imagePath: json['imagePath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'part': part,
        'detail': detail,
        if (imagePath != null) 'imagePath': imagePath,
      };
}

class Creature {
  final String id;
  final String nameJa;
  final String nameEn;
  final String nameScientific;
  final CreatureType type;
  final List<Habitat> habitats;
  final String description;
  final List<IdentificationTip> tips;
  final String imagePath;
  final int rarity;

  /// 環境省レッドリストの区分（CR=絶滅危惧IA類 / EN=IB類 / VU=II類 / NT=準絶滅危惧）。null=指定なし
  final String? redList;
  bool discovered;

  Creature({
    required this.id,
    required this.nameJa,
    required this.nameEn,
    required this.nameScientific,
    required this.type,
    required this.habitats,
    required this.description,
    required this.tips,
    required this.imagePath,
    required this.rarity,
    this.redList,
    this.discovered = false,
  });

  factory Creature.fromJson(Map<String, dynamic> json) {
    return Creature(
      id: json['id'] as String,
      nameJa: json['nameJa'] as String,
      nameEn: json['nameEn'] as String,
      nameScientific: json['nameScientific'] as String,
      type: CreatureType.values.firstWhere(
        (e) => e.name == (json['type'] as String),
        orElse: () => CreatureType.plant,
      ),
      habitats: (json['habitats'] as List<dynamic>)
          .map((h) => Habitat.values.firstWhere(
                (e) => e.name == (h as String),
                orElse: () => Habitat.forest,
              ))
          .toList(),
      description: json['description'] as String,
      tips: (json['tips'] as List<dynamic>)
          .map((t) => IdentificationTip.fromJson(t as Map<String, dynamic>))
          .toList(),
      imagePath: json['imagePath'] as String,
      rarity: json['rarity'] as int,
      redList: json['redList'] as String?,
    );
  }

  int get expReward => rarity * 10;

  /// 絶滅のおそれが高い種（CR・EN・VU）
  bool get endangered => redList == 'CR' || redList == 'EN' || redList == 'VU';

  String? get redLabel {
    switch (redList) {
      case 'CR': return '絶滅危惧IA類';
      case 'EN': return '絶滅危惧IB類';
      case 'VU': return '絶滅危惧II類';
      case 'NT': return '準絶滅危惧';
      default: return null;
    }
  }

  /// 見つけたときのボーナス（予算）
  int get discoveryBonus {
    switch (redList) {
      case 'CR': return 40;
      case 'EN': return 25;
      case 'VU': return 15;
      case 'NT': return 8;
      default: return 0;
    }
  }

  String get rarityLabel {
    switch (rarity) {
      case 1: return '★☆☆☆☆ よく見られる';
      case 2: return '★★☆☆☆ 時々見られる';
      case 3: return '★★★☆☆ 珍しい';
      case 4: return '★★★★☆ 非常に珍しい';
      case 5: return '★★★★★ 超レア';
      default: return '不明';
    }
  }

  String get typeLabel {
    switch (type) {
      case CreatureType.plant: return '植物';
      case CreatureType.bird: return '鳥';
      case CreatureType.fish: return '魚';
      case CreatureType.animal: return '動物';
    }
  }
}
