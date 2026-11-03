import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/species_hints.dart';
import '../models/creature.dart';
import '../providers/conservation_provider.dart';

const _gold = Color(0xFFE8B96A);

/// まだ出会っていない種の、ふわっとしたヒントと、予想メモ
Future<void> showHintDialog(BuildContext context, WidgetRef ref, Creature c) {
  final n = ref.read(conservationProvider.notifier);
  final ctrl = TextEditingController(text: ref.read(conservationProvider).memos[c.id] ?? '');
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF0E0C09),
      title: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: _gold, size: 20),
          const SizedBox(width: 8),
          Text('？？？  ${c.typeLabel}', style: const TextStyle(color: _gold, fontSize: 16, letterSpacing: 2)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(vagueHint(c), style: const TextStyle(fontSize: 14, height: 1.6)),
            const SizedBox(height: 10),
            const Text('ネットで調べて、どんな生き物か推測してみよう。場所や条件を変えると出会えるかも。',
                style: TextStyle(fontSize: 11, color: Colors.white54, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: '予想メモ',
                hintText: '例：〇〇かも？ 山の高いところを探す',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            n.setMemo(c.id, ctrl.text);
            Navigator.pop(context);
          },
          child: const Text('メモして閉じる'),
        ),
      ],
    ),
  );
}
