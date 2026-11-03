class PlayerState {
  int level;
  int exp;
  int expToNextLevel;
  List<String> discoveredIds;
  int currentArea;

  PlayerState({
    this.level = 1,
    this.exp = 0,
    this.expToNextLevel = 50,
    List<String>? discoveredIds,
    this.currentArea = 0,
  }) : discoveredIds = discoveredIds ?? [];

  bool isDiscovered(String id) => discoveredIds.contains(id);

  int get totalDiscovered => discoveredIds.length;

  double get expProgress => exp / expToNextLevel;

  String get areaName {
    switch (currentArea) {
      case 0: return '森';
      case 1: return '池';
      case 2: return '川';
      case 3: return '海';
      default: return '森';
    }
  }

  bool get canAccessPond => level >= 3;
  bool get canAccessRiver => level >= 6;
  bool get canAccessOcean => level >= 10;

  Map<String, dynamic> toJson() => {
        'level': level,
        'exp': exp,
        'expToNextLevel': expToNextLevel,
        'discoveredIds': discoveredIds,
        'currentArea': currentArea,
      };

  factory PlayerState.fromJson(Map<String, dynamic> json) {
    return PlayerState(
      level: json['level'] as int? ?? 1,
      exp: json['exp'] as int? ?? 0,
      expToNextLevel: json['expToNextLevel'] as int? ?? 50,
      discoveredIds: (json['discoveredIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      currentArea: json['currentArea'] as int? ?? 0,
    );
  }

  PlayerState copyWith({
    int? level,
    int? exp,
    int? expToNextLevel,
    List<String>? discoveredIds,
    int? currentArea,
  }) {
    return PlayerState(
      level: level ?? this.level,
      exp: exp ?? this.exp,
      expToNextLevel: expToNextLevel ?? this.expToNextLevel,
      discoveredIds: discoveredIds ?? List.from(this.discoveredIds),
      currentArea: currentArea ?? this.currentArea,
    );
  }
}
