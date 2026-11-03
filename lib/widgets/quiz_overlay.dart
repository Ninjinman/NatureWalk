import 'dart:math';
import 'package:flutter/material.dart';
import '../models/creature.dart';
import '../data/species_database.dart';

class QuizOverlay extends StatefulWidget {
  final Creature creature;
  final VoidCallback onClose;
  final void Function(bool correct, int expGained) onResult;

  const QuizOverlay({
    super.key,
    required this.creature,
    required this.onClose,
    required this.onResult,
  });

  @override
  State<QuizOverlay> createState() => _QuizOverlayState();
}

class _QuizOverlayState extends State<QuizOverlay> {
  late _QuizQuestion _question;
  int? _selected;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _question = _generateQuestion(widget.creature);
  }

  _QuizQuestion _generateQuestion(Creature c) {
    final rng = Random();
    final tip = c.tips[rng.nextInt(c.tips.length)];
    final correct = tip.detail;
    final question = '${c.nameJa}の「${tip.part}」の特徴は？';

    // 他の生き物から wrong choices を生成
    final others = SpeciesDatabase.instance.all
        .where((x) => x.id != c.id)
        .toList()
      ..shuffle(rng);

    final wrongs = <String>[];
    for (final other in others) {
      if (wrongs.length >= 3) break;
      if (other.tips.isNotEmpty) {
        wrongs.add(other.tips[rng.nextInt(other.tips.length)].detail);
      }
    }
    while (wrongs.length < 3) {
      wrongs.add('特徴的な点はない');
    }

    final choices = [correct, ...wrongs.take(3)]..shuffle(rng);
    final correctIndex = choices.indexOf(correct);

    return _QuizQuestion(
      question: question,
      choices: choices,
      correctIndex: correctIndex,
    );
  }

  void _answer(int idx) {
    if (_answered) return;
    setState(() {
      _selected = idx;
      _answered = true;
    });

    final correct = idx == _question.correctIndex;
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final exp = correct ? widget.creature.expReward : 0;
      widget.onResult(correct, exp);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2A3A),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'クイズ',
                style: TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 14,
                    letterSpacing: 2),
              ),
              const SizedBox(height: 12),
              Text(
                _question.question,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ...List.generate(_question.choices.length, (i) {
                Color bg = const Color(0xFF2C3E50);
                Color border = Colors.transparent;
                if (_answered && _selected == i) {
                  bg = i == _question.correctIndex
                      ? Colors.green.shade700
                      : Colors.red.shade700;
                  border = i == _question.correctIndex
                      ? Colors.greenAccent
                      : Colors.redAccent;
                } else if (_answered && i == _question.correctIndex) {
                  bg = Colors.green.shade800;
                  border = Colors.greenAccent;
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => _answer(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border, width: 2),
                      ),
                      child: Text(
                        '${['A', 'B', 'C', 'D'][i]}. ${_question.choices[i]}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ),
                );
              }),
              if (_answered) ...[
                const SizedBox(height: 8),
                Text(
                  _selected == _question.correctIndex
                      ? '✅ 正解！ +${widget.creature.expReward} EXP'
                      : '❌ 不正解...',
                  style: TextStyle(
                    color: _selected == _question.correctIndex
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuizQuestion {
  final String question;
  final List<String> choices;
  final int correctIndex;
  const _QuizQuestion({
    required this.question,
    required this.choices,
    required this.correctIndex,
  });
}
