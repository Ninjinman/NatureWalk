import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 和のチルピアノ風のBGM。音源ファイルは使わず、ピアノ風の音を端末内で合成して流す。
/// 進行は Am9 → Fmaj7 → Cadd9 → G6、旋律はペンタトニック。ブラウザの制限で、最初のタップのあとに鳴り始める。
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

  static double _hz(int midi) => 440.0 * pow(2, (midi - 69) / 12);

  static Uint8List _synthesize() {
    final n = _sr * _seconds;
    final mix = Float64List(n);

    // ピアノ風の音：倍音を重ね、ハンマーの立ち上がり→高い音ほど速く減衰
    void piano(double start, int midi, double gain) {
      final i0 = (start * _sr).round();
      if (i0 >= n) return;
      final f = _hz(midi);
      final dur = min(n - i0, (_sr * 3.2).round());
      final decay = exp(-(0.9 + (midi - 40) * 0.02) / _sr);
      const amps = [1.0, 0.45, 0.22, 0.1];
      final w = 2 * pi_ * f / _sr;
      var env = 1.0;
      // 高次倍音ほど早く消える（やわらかい音色）。減衰率は先に求めておく
      final dk = [for (var k = 0; k < amps.length; k++) pow(decay, k * 0.5).toDouble()];
      final ek = List<double>.filled(amps.length, 1.0);
      for (var i = 0; i < dur; i++) {
        var v = 0.0;
        for (var k = 0; k < amps.length; k++) {
          v += amps[k] * ek[k] * sin(w * (k + 1) * i * (1 + 0.0004 * k * k));
          ek[k] *= dk[k];
        }
        final atk = i < 110 ? i / 110.0 : 1.0;
        mix[i0 + i] += v * env * atk * gain;
        env *= decay;
      }
    }

    // 8小節（1小節=8秒）。Am9 → Fmaj7 → Cadd9 → G6 を2周
    const chords = <List<int>>[
      [45, 52, 60, 64, 67],
      [41, 48, 57, 60, 64],
      [48, 55, 60, 64, 67],
      [43, 50, 59, 62, 64],
    ];
    const arp = [0, 1, 2, 3, 4, 3, 2, 1];
    // 右手の旋律（拍の位置, MIDI）。ペンタトニックで、音数は少なく間を多めに
    const melody = <List<(double, int)>>[
      [(1, 76), (3, 79), (5.5, 76)],
      [(1, 77), (3, 76), (5, 72)],
      [(0.5, 79), (2.5, 76), (4, 74), (6, 72)],
      [(1, 74), (3, 71), (5, 74), (6.5, 76)],
      [(0, 81), (2, 79), (4, 76)],
      [(1, 77), (2.5, 76), (4, 72), (6, 69)],
      [(0, 76), (1.5, 79), (3, 84), (5, 79)],
      [(1, 79), (3, 76), (4.5, 74), (6, 71)],
    ];
    for (var bar = 0; bar < 8; bar++) {
      final t0 = bar * 8.0;
      final ch = chords[bar % 4];
      for (var b = 0; b < 8; b++) {
        piano(t0 + b, ch[arp[b]], b == 0 ? 0.30 : 0.17);
      }
      for (final (off, m) in melody[bar]) {
        piano(t0 + off, m, 0.26);
      }
    }

    // 残響（簡単なコムフィルタ）
    final out = Float64List(n);
    const taps = [(0.19, 0.30), (0.41, 0.24), (0.73, 0.18), (1.1, 0.10)];
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
