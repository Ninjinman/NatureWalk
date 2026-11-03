import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/species_traits.dart';
import '../models/creature.dart';

const _gold = Color(0xFFE8B96A);

String creaturePhotoPath(Creature c) => 'assets/images/creatures/${c.id}.jpg';

/// CustomPainter で使う写真のキャッシュ（ui.Image）と、クレジット情報
class CreaturePhotos {
  static final Map<String, ui.Image> _images = {};
  static Map<String, dynamic> _credits = {};
  static bool _creditsLoaded = false;

  static ui.Image? of(String id) => _images[id];

  static Future<void> preload(Iterable<Creature> creatures) async {
    await loadCredits();
    for (final c in creatures) {
      if (_images.containsKey(c.id)) continue;
      try {
        final data = await rootBundle.load(creaturePhotoPath(c));
        final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(), targetWidth: 220);
        _images[c.id] = (await codec.getNextFrame()).image;
      } catch (_) {
        // 写真が無い種は図形表示にフォールバック
      }
    }
  }

  static Future<void> loadCredits() async {
    if (_creditsLoaded) return;
    try {
      final raw = await rootBundle.loadString('assets/data/image_credits.json');
      _credits = json.decode(raw) as Map<String, dynamic>;
    } catch (_) {}
    _creditsLoaded = true;
  }

  static String? creditOf(String id) {
    final c = _credits[id] as Map<String, dynamic>?;
    if (c == null) return null;
    final author = (c['author'] as String?)?.trim() ?? '';
    final license = (c['license'] as String?) ?? '';
    return '写真: ${author.isEmpty ? '不明' : author} / $license (Wikimedia Commons)';
  }
}

/// 丸い写真サムネイル
class CreatureThumb extends StatelessWidget {
  final Creature creature;
  final double size;
  final bool dim;
  const CreatureThumb({super.key, required this.creature, this.size = 40, this.dim = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: dim ? Colors.white24 : _gold.withValues(alpha: 0.8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ColorFiltered(
        colorFilter: dim
            ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
            : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
        child: Image.asset(
          creaturePhotoPath(creature),
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
          errorBuilder: (_, __, ___) => const Icon(Icons.eco, color: Colors.white38),
        ),
      ),
    );
  }
}

/// 種の詳細：写真・見分けるポイント・好む環境・クレジット
Future<void> showCreatureDetail(BuildContext context, Creature c) async {
  await CreaturePhotos.loadCredits();
  if (!context.mounted) return;
  final traits = speciesTraits[c.id];
  final credit = CreaturePhotos.creditOf(c.id);
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: const Color(0xFF0E0C09),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.asset(
                    creaturePhotoPath(c),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: Colors.black26,
                      child: Center(child: Icon(Icons.image_not_supported, color: Colors.white24)),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.nameJa, style: const TextStyle(fontSize: 22, color: _gold, letterSpacing: 2)),
                    Text('${c.nameEn} / ${c.nameScientific}',
                        style: const TextStyle(fontSize: 11, color: Colors.white54)),
                    const SizedBox(height: 4),
                    Text('${c.typeLabel}   ${c.rarityLabel}',
                        style: const TextStyle(fontSize: 11, color: Colors.white38)),
                    if (c.redLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: c.endangered ? _gold : Colors.white30),
                            borderRadius: BorderRadius.circular(10),
                            color: c.endangered ? _gold.withValues(alpha: 0.12) : null,
                          ),
                          child: Text('${c.endangered ? '★ ' : ''}${c.redLabel}（環境省レッドリスト）',
                              style: TextStyle(fontSize: 11, color: c.endangered ? _gold : Colors.white54)),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(c.description, style: const TextStyle(fontSize: 13, height: 1.5)),
                    if (c.tips.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const _Heading('見分けるポイント'),
                      for (final t in c.tips)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 64,
                                child: Text(t.part,
                                    style: const TextStyle(fontSize: 12, color: _gold)),
                              ),
                              Expanded(
                                child: Text(t.detail,
                                    style: const TextStyle(fontSize: 12, height: 1.4)),
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (traits != null) ...[
                      const SizedBox(height: 14),
                      const _Heading('育つ環境'),
                      for (final e in traits.ranges.entries)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '${e.key.label}：${e.key.format(e.value.$1)} 〜 ${e.key.format(e.value.$2)}',
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ),
                      if (c.type == CreatureType.bird)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('※ 餌となる動植物が多いほど増えます',
                              style: TextStyle(fontSize: 12, color: Colors.white54)),
                        ),
                    ],
                    if (credit != null) ...[
                      const SizedBox(height: 14),
                      Text(credit, style: const TextStyle(fontSize: 9, color: Colors.white30)),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: Builder(
                        builder: (ctx) => TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('閉じる'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 12, color: Colors.white54, letterSpacing: 3));
}
