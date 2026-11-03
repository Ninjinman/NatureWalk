import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/creature.dart';

class SpeciesDatabase {
  static SpeciesDatabase? _instance;
  static SpeciesDatabase get instance => _instance ??= SpeciesDatabase._();
  SpeciesDatabase._();

  List<Creature>? _plants;
  List<Creature>? _birds;
  List<Creature>? _fish;
  List<Creature>? _all;

  Future<void> initialize() async {
    _plants = await _load('assets/data/plants.json');
    _birds = await _load('assets/data/birds.json');
    _fish = await _load('assets/data/fish.json');
    _all = [..._plants!, ..._birds!, ..._fish!];
  }

  Future<List<Creature>> _load(String path) async {
    final raw = await rootBundle.loadString(path);
    final list = json.decode(raw) as List<dynamic>;
    return list.map((e) => Creature.fromJson(e as Map<String, dynamic>)).toList();
  }

  List<Creature> get plants => _plants ?? [];
  List<Creature> get birds => _birds ?? [];
  List<Creature> get fish => _fish ?? [];
  List<Creature> get all => _all ?? [];

  List<Creature> byHabitat(Habitat habitat) =>
      all.where((c) => c.habitats.contains(habitat)).toList();

  List<Creature> byType(CreatureType type) =>
      all.where((c) => c.type == type).toList();

  Creature? findById(String id) {
    try {
      return all.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Creature> spawnable(Habitat habitat, {int maxRarity = 3}) =>
      byHabitat(habitat).where((c) => c.rarity <= maxRarity).toList();
}
