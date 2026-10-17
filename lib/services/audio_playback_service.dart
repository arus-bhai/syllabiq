import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/wav_encoder.dart';

/// Buffers the full PCM response before playing it (trade-off: no
/// progressive/live playback, but simple and reliable). See the
/// true-streaming discussion earlier — swap this out for
/// flutter_pcm_sound-based chunk scheduling later if you need audio to
/// start before generation finishes.
class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playPcmStream(
    Stream<List<int>> pcmStream, {
    int sampleRate = 24000,
  }) async {
    final builder = BytesBuilder();
    await for (final chunk in pcmStream) {
      builder.add(chunk);
    }
    final pcmBytes = builder.toBytes();
    if (pcmBytes.isEmpty) return;

    final samples = pcmBytes.buffer.asInt16List(
      pcmBytes.offsetInBytes,
      pcmBytes.lengthInBytes ~/ 2,
    );
    await playInt16Samples(samples, sampleRate: sampleRate);
  }

  /// Plays already-decoded 16-bit PCM samples directly — used for testing
  /// playback of a locally recorded clip without a network round trip.
  Future<void> playInt16Samples(
    Int16List samples, {
    required int sampleRate,
  }) async {
    if (samples.isEmpty) return;
    final wavBytes = encodeWav(samples, sampleRate: sampleRate);
    await _playWavBytes(wavBytes);
  }

  Future<void> _playWavBytes(Uint8List wavBytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/playback_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(wavBytes);

    final completer = Completer<void>();
    late final StreamSubscription sub;
    sub = _player.onPlayerComplete.listen((_) {
      sub.cancel();
      if (!completer.isCompleted) completer.complete();
    });

    await _player.play(DeviceFileSource(file.path));
    await completer.future;

    if (await file.exists()) {
      await file.delete();
    }
  }

  void dispose() {
    _player.dispose();
  }
}
