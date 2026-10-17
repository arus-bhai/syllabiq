import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';

/// Streams raw PCM to the speaker as chunks arrive, via flutter_sound's
/// startPlayerFromStream/feedUint8FromStream API — the Flutter equivalent
/// of the Web Audio API scheduling used on the HTML test page, so playback
/// can start before the full response has finished generating.
///
/// Requires a CURRENT flutter_sound version (9.27.0+). An older pin
/// (9.2.13) was tried first for API stability but hit a hard wall: its
/// Android code targets Flutter's old v1 embedding (PluginRegistry.
/// Registrar), which was removed from the engine entirely — not fixable
/// via Gradle config, only by using a version built against v2 embedding.
class LivePcmPlayer {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _openDone = false;

  Uint8List? _leftoverByte;
  int _samplesFed = 0;
  DateTime? _firstFeedTime;

  Future<void> _ensureOpen() async {
    if (_openDone) return;
    await _player.openPlayer();
    _openDone = true;
  }

  /// Feeds chunks to the speaker as they arrive from [pcmStream]. Completes
  /// once the fed audio has finished playing out — estimated from total
  /// samples fed vs elapsed time, since flutter_sound doesn't expose a
  /// direct "finished playing" callback to await on for stream-fed audio.
  Future<void> playStream(
      Stream<List<int>> pcmStream, {
        int sampleRate = 24000,
      }) async {
    await _ensureOpen();

    _leftoverByte = null;
    _samplesFed = 0;
    _firstFeedTime = null;

    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: sampleRate,
      bufferSize: 8192, // required as of 9.30.0; must be a power of 2
      interleaved: true, // required in some versions; mono audio here
    );

    final streamStart = DateTime.now();
    var chunkCount = 0;

    await for (final chunk in pcmStream) {
      if (chunk.isEmpty) continue;
      final aligned = _alignToSampleBoundary(Uint8List.fromList(chunk));
      if (aligned.isEmpty) continue;

      chunkCount++;
      if (_firstFeedTime == null) {
        _firstFeedTime = DateTime.now();
        debugPrint(
          '[LivePcmPlayer] first chunk fed after '
              '${_firstFeedTime!.difference(streamStart).inMilliseconds}ms '
              '(${aligned.length} bytes)',
        );
      }
      _samplesFed += aligned.length ~/ 2; // 16-bit samples

      // foodSink/FoodData was deprecated in 9.27.0 and is unavailable on
      // current versions — feedUint8FromStream is the current push API.
      await _player.feedUint8FromStream(aligned);
    }

    debugPrint(
      '[LivePcmPlayer] stream done — $chunkCount chunks, $_samplesFed samples total',
    );

    // Feeding finishes well before playback actually does — wait out
    // whatever's left based on total duration fed vs time elapsed.
    if (_firstFeedTime != null && _samplesFed > 0) {
      final totalDuration = Duration(
        milliseconds: (_samplesFed / sampleRate * 1000).round(),
      );
      final elapsed = DateTime.now().difference(_firstFeedTime!);
      final remaining = totalDuration - elapsed;
      if (remaining > Duration.zero) {
        await Future.delayed(remaining + const Duration(milliseconds: 150));
      }
    }

    await _player.stopPlayer();
  }

  /// foodSink takes raw bytes directly — still need to carry over a
  /// leftover odd byte across chunk boundaries so we never feed a
  /// half-sample, same handling as the earlier Int16-conversion approach.
  Uint8List _alignToSampleBoundary(Uint8List bytes) {
    var data = bytes;
    if (_leftoverByte != null) {
      final combined = Uint8List(bytes.length + 1);
      combined[0] = _leftoverByte![0];
      combined.setRange(1, combined.length, bytes);
      data = combined;
      _leftoverByte = null;
    }
    if (data.length.isOdd) {
      _leftoverByte = Uint8List.fromList([data.last]);
      data = data.sublist(0, data.length - 1);
    }
    return data;
  }

  void dispose() {
    if (_openDone) {
      _player.closePlayer();
    }
  }
}