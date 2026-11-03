import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/species_database.dart';
import '../data/species_hints.dart';
import '../models/creature.dart';
import '../providers/conservation_provider.dart';
import '../widgets/creature_photo.dart';
import '../widgets/hint_dialog.dart';
import 'hakoniwa_screen.dart' show kGold, kInk;

/// 図鑑：出会った種は写真と名前、まだの種は「？？？」とヒント
class EncyclopediaScreen extends ConsumerWidget {
  const EncyclopediaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(conservationProvider);
    final dex = SpeciesDatabase.instance.all.length;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: kInk,
        appBar: AppBar(
          backgroundColor: const Color(0xFF0E0C09),
          title: Text('図鑑  ${s.discovered.length} / $dex', style: const TextStyle(letterSpacing: 3)),
          bottom: const TabBar(
            indicatorColor: kGold,
            labelColor: kGold,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.local_florist, size: 18), text: '植物'),
              Tab(icon: Icon(Icons.flutter_dash, size: 18), text: '鳥'),
              Tab(icon: Icon(Icons.set_meal, size: 18), text: '魚'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _Dex(type: CreatureType.plant),
            _Dex(type: CreatureType.bird),
            _Dex(type: CreatureType.fish),
          ],
        ),
      ),
    );
  }
}

class _Dex extends ConsumerWidget {
  final CreatureType type;
  const _Dex({required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(conservationProvider);
    final list = SpeciesDatabase.instance.byType(type);
    final found = list.where((c) => s.discovered.contains(c.id)).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Text('$found / ${list.length} 種に出会った', style: const TextStyle(fontSize: 12, color: Colors.white70)),
              const SizedBox(width: 12),
              Expanded(
                child: LinearProgressIndicator(
                  value: list.isEmpty ? 0 : found / list.length,
                  minHeight: 3,
                  color: kGold,
                  backgroundColor: Colors.white10,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.72,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) => _Card(creature: list[i]),
          ),
        ),
      ],
    );
  }
}

class _Card extends ConsumerWidget {
  final Creature creature;
  const _Card({required this.creature});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(conservationProvider);
    final known = s.discovered.contains(creature.id);
    final c = creature;
    final rare = known && c.endangered;
    final memo = s.memos[c.id];
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => known ? showCreatureDetail(context, c) : showHintDialog(context, ref, c),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF14110C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: rare ? kGold : Colors.white12, width: rare ? 1.6 : 1),
          boxShadow: rare ? [BoxShadow(color: kGold.withValues(alpha: 0.35), blurRadius: 10)] : null,
        ),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (_, box) {
                  final size = box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight;
                  return known
                      ? CreatureThumb(creature: c, size: size)
                      : Container(
                          width: size,
                          height: size,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1C1710)),
                          child: const Icon(Icons.help_outline, color: Colors.white24, size: 34),
                        );
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              known ? '${c.endangered ? '★ ' : ''}${c.nameJa}' : '？？？',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: rare ? kGold : (known ? Colors.white : Colors.white54)),
            ),
            if (!known)
              Text(
                memo != null && memo.isNotEmpty ? 'メモ：$memo' : vagueHint(c),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 8, color: Colors.white38, height: 1.25),
              ),
          ],
        ),
      ),
    );
  }
}
