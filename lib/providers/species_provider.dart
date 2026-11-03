import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/species_database.dart';
import '../models/creature.dart';

final speciesDatabaseProvider = FutureProvider<SpeciesDatabase>((ref) async {
  final db = SpeciesDatabase.instance;
  await db.initialize();
  return db;
});

final allCreaturesProvider = Provider<List<Creature>>((ref) {
  return ref.watch(speciesDatabaseProvider).maybeWhen(
        data: (db) => db.all,
        orElse: () => [],
      );
});

final plantListProvider = Provider<List<Creature>>((ref) {
  return ref.watch(speciesDatabaseProvider).maybeWhen(
        data: (db) => db.plants,
        orElse: () => [],
      );
});

final birdListProvider = Provider<List<Creature>>((ref) {
  return ref.watch(speciesDatabaseProvider).maybeWhen(
        data: (db) => db.birds,
        orElse: () => [],
      );
});

final fishListProvider = Provider<List<Creature>>((ref) {
  return ref.watch(speciesDatabaseProvider).maybeWhen(
        data: (db) => db.fish,
        orElse: () => [],
      );
});

final habitatCreaturesProvider =
    Provider.family<List<Creature>, Habitat>((ref, habitat) {
  return ref.watch(speciesDatabaseProvider).maybeWhen(
        data: (db) => db.byHabitat(habitat),
        orElse: () => [],
      );
});
