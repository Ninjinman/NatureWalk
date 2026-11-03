import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/player_state.dart';

final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier();
});

class PlayerNotifier extends StateNotifier<PlayerState> {
  static const _boxKey = 'player_state';
  static const _dataKey = 'data';
  late Box _box;

  PlayerNotifier() : super(PlayerState()) {
    _init();
  }

  Future<void> _init() async {
    _box = await Hive.openBox(_boxKey);
    final raw = _box.get(_dataKey);
    if (raw != null) {
      try {
        state = PlayerState.fromJson(json.decode(raw as String) as Map<String, dynamic>);
      } catch (_) {
        state = PlayerState();
      }
    }
  }

  void _save() {
    _box.put(_dataKey, json.encode(state.toJson()));
  }

  void addExp(int amount) {
    int newExp = state.exp + amount;
    int newLevel = state.level;
    int newExpToNext = state.expToNextLevel;

    while (newExp >= newExpToNext) {
      newExp -= newExpToNext;
      newLevel++;
      newExpToNext = _calcExpToNext(newLevel);
    }

    state = state.copyWith(
      exp: newExp,
      level: newLevel,
      expToNextLevel: newExpToNext,
    );
    _save();
  }

  int _calcExpToNext(int level) => (50 * level * (1 + level * 0.1)).round();

  void discoverCreature(String id) {
    if (state.isDiscovered(id)) return;
    final ids = [...state.discoveredIds, id];
    state = state.copyWith(discoveredIds: ids);
    _save();
  }

  void changeArea(int areaIndex) {
    if (areaIndex < 0 || areaIndex > 3) return;
    if (areaIndex == 1 && !state.canAccessPond) return;
    if (areaIndex == 2 && !state.canAccessRiver) return;
    if (areaIndex == 3 && !state.canAccessOcean) return;
    state = state.copyWith(currentArea: areaIndex);
    _save();
  }

  void reset() {
    state = PlayerState();
    _save();
  }
}
