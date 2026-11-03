import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 和風の落ち着いたBGM。音源ファイルは使わず、琴のような撥弦音を端末内で合成して流す。
/// 音階は都節（D E♭ G A B♭）。ブラウザの制限で、最初のタップのあとに鳴り始める。
class Bgm {
  Bgm._();

  static final ValueNotifier<bool> on = ValueNotifier(true);
  static AudioPlayer? _player;
  static bool _starting = false;
  static bool _playing = false;

  /// 最初の操作のあとに呼ぶ（何度呼んでもよい）
  static Future<void> ensureStarted() async {
    if (_playing || _starting || !on.value) return;
    _starting = true;
    try {
      final wav = _synthesize();
      final p = _player ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(0.55);
      await p.play(BytesSource(wav, mimeType: 'audio/wav'));
      _playing = true;
    } catch (e) {
      debugPrint('BGM を開始できませんでした: $e');
    } finally {
      _starting = false;
    }
  }

  static Future<void> toggle() async {
    on.value = !on.value;
    if (on.value) {
      if (_playing) {
        await _player?.resume();
      } else {
        await ensureStarted();
      }
    } else {
      await _player?.pause();
    }
  }

  // ---- 合成 ----------------------------------------------------------------

  static const _sr = 22050;
  static const _seconds = 64;

  /// 都節（根音 D4 = 293.66Hz）。度数→周波数
  static double _freq(int degree) {
    const steps = [0, 1, 5, 7, 8]; // D, E♭, G, A, B♭（半音）
    final oct = (degree / 5).floor();
    final semis = steps[degree - oct * 5] + 12 * oct;
    return 293.66 * pow(2, semis / 12);
  }

  static Uint8List _synthesize() {
    final n = _sr * _seconds;
    final mix = Float64List(n);
    final rng = Random(7);

    // 撥弦（Karplus–Strong）を足し込む
    void pluck(double start, double f, double gain, {double decay = 0.9965}) {
      final i0 = (start * _sr).round();
      final len = max(2, (_sr / f).round());
      final buf = Float64List(len);
      for (var i = 0; i < len; i++) {
        buf[i] = rng.nextDouble() * 2 - 1;
      }
      var prev = 0.0;
      final dur = min(n - i0, (_sr * 5.0).round());
      for (var i = 0; i < dur; i++) {
        final k = i % len;
        final cur = buf[k];
        final v = decay * 0.5 * (cur + prev);
        buf[k] = v;
        prev = cur;
        final env = i < 80 ? i / 80.0 : 1.0;
        mix[i0 + i] += v * gain * env;
      }
    }

    // 旋律：度数（5で1オクターブ上）と拍の位置。ゆっくり、間を多めに
    const phrases = <List<(double, int)>>[
      [(0, 5), (1.5, 7), (3, 8), (5, 7), (6.5, 5)],
      [(0, 8), (2, 7), (3.5, 5), (5, 3), (7, 2)],
      [(0, 3), (1.5, 5), (3, 7), (4.5, 8), (6, 10)],
      [(0, 10), (2, 8), (3.5, 7), (5, 5), (7.5, 3)],
      [(0, 5), (2, 3), (3, 2), (5, 0), (7, 2)],
      [(0, 2), (1.5, 3), (3, 5), (5, 3), (6.5, 0)],
    ];
    const beat = 1.0; // 1拍 = 1秒
    var t = 1.0;
    var pi = 0;
    while (t < _seconds - 8) {
      final ph = phrases[pi % phrases.length];
      for (final (off, deg) in ph) {
        pluck(t + off * beat, _freq(deg), 0.30);
      }
      // 低い根音を、フレーズの頭にゆっくり添える
      pluck(t, _freq(-5) , 0.28, decay: 0.9985);
      if (pi % 2 == 1) pluck(t + 4 * beat, _freq(-2), 0.2, decay: 0.998);
      t += 9.5 * beat;
      pi++;
    }

    // 尺八のようなやわらかい持続音（根音と5度）を、ごく小さく
    for (var i = 0; i < n; i++) {
      final s = i / _sr;
      final swell = 0.5 + 0.5 * sin(2 * pi_ * s / 16.0);
      final breath = sin(2 * pi_ * 146.83 * s) + 0.5 * sin(2 * pi_ * 220.0 * s);
      mix[i] += breath * 0.035 * swell;
    }

    // 残響（簡単なコムフィルタ）
    final out = Float64List(n);
    const taps = [(0.23, 0.32), (0.37, 0.24), (0.61, 0.16)];
    for (var i = 0; i < n; i++) {
      var v = mix[i];
      for (final (d, g) in taps) {
        final j = i - (d * _sr).round();
        if (j >= 0) v += mix[j] * g;
      }
      out[i] = v;
    }

    // 正規化して 16bit WAV に
    var peak = 0.0;
    for (final v in out) {
      peak = max(peak, v.abs());
    }
    final scale = peak == 0 ? 0 : 0.85 / peak;
    final data = ByteData(44 + n * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + n * 2, Endian.little);
    str(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, _sr, Endian.little);
    data.setUint32(28, _sr * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, n * 2, Endian.little);
    final fade = _sr * 2; // 継ぎ目で音が途切れないよう、始めと終わりをなめらかに
    for (var i = 0; i < n; i++) {
      var v = out[i] * scale;
      if (i < fade) v *= i / fade;
      if (i > n - fade) v *= (n - i) / fade;
      data.setInt16(44 + i * 2, (v * 32767).round().clamp(-32768, 32767), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static const pi_ = 3.141592653589793;
}
