import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/glow_tree.dart';
import '../models/creature.dart';
import '../services/real_weather.dart';
import 'encyclopedia_screen.dart';
import 'hakoniwa_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kInk,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),
                    GlowTree(size: min(260, max(140, box.maxHeight * 0.3))),
                    const SizedBox(height: 12),
                    const Text(
                      'NatureWalk',
                      style: TextStyle(
                        fontSize: 38,
                        letterSpacing: 6,
                        color: Colors.white,
                        shadows: [Shadow(blurRadius: 18, color: kGold)],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '小さな自然を育てる箱庭',
                      style: TextStyle(fontSize: 13, letterSpacing: 4, color: Colors.white54),
                    ),
                    const SizedBox(height: 12),
                    const _WeatherLine(),
                    const SizedBox(height: 22),
                    _menuButton(
                      context,
                      label: '箱庭をはじめる',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const HakoniwaScreen()),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _menuButton(
                      context,
                      label: '図鑑',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EncyclopediaScreen()),
                      ),
                    ),
                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuButton(BuildContext context,
      {required String label, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: kGold,
            side: BorderSide(color: kGold.withValues(alpha: 0.7)),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 16, letterSpacing: 6)),
        ),
      ),
    );
  }
}


/// 現実の天気（ゲームの季節・気温・予報と連動する）
class _WeatherLine extends ConsumerWidget {
  const _WeatherLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(realInfoProvider);
    return w.when(
      data: (m) {
        final d = m[Habitat.forest] ?? m.values.first;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(d.icon, size: 16, color: kGold),
            const SizedBox(width: 6),
            Flexible(
              child: Text('現実の天気  ${d.summary}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ),
          ],
        );
      },
      loading: () => const Text('現実の天気を取得中…', style: TextStyle(fontSize: 12, color: Colors.white38)),
      error: (_, __) => const Text('天気を取得できませんでした', style: TextStyle(fontSize: 12, color: Colors.white38)),
    );
  }
}
