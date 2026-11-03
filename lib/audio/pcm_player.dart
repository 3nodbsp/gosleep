import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

import 'soundscape_synth.dart';

/// 基于 flutter_pcm_sound 的实时 PCM 播放器。
///
/// 持续向原生音频层喂数据（提前缓冲约 1.2 秒），
/// 音色由 [SoundscapeSynth] 实时合成，输出频率变化即时生效。
class PcmPlayer {
  PcmPlayer({this.sampleRate = 48000});

  final int sampleRate;

  SoundscapeSynth? _synth;
  bool _running = false;
  bool _prepared = false;

  static const int _chunkFrames = 4800; // 100ms @48kHz
  static const int _feedThreshold = 4800; // 剩余低于 100ms 时回调补料

  bool get isRunning => _running;

  Future<void> start(SoundscapeSynth synth) async {
    _synth = synth;
    _running = true;

    if (!_prepared) {
      await FlutterPcmSound.setSampleRate(sampleRate);
      await FlutterPcmSound.setNumChannels(1);
      FlutterPcmSound.setFeedThreshold(_feedThreshold);
      FlutterPcmSound.setFeedCallback((int remain) => _onFeed(remain));
      _prepared = true;
    }

    await FlutterPcmSound.start();
    // 预填充约 1.2 秒，避免启动爆音/断流。
    _onFeed(0);
  }

  void _onFeed(int remain) {
    if (!_running) return;
    final s = _synth;
    if (s == null) return;
    var buffered = remain;
    while (_running && buffered < sampleRate + _chunkFrames * 2) {
      final Uint8List chunk = s.generateChunk(_chunkFrames);
      FlutterPcmSound.feed(chunk);
      buffered += _chunkFrames;
    }
  }

  Future<void> stop() async {
    _running = false;
    try {
      await FlutterPcmSound.stop();
    } catch (_) {
      // 未启动时停止的容错。
    }
  }
}
