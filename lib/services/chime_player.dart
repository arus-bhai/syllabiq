import 'package:audioplayers/audioplayers.dart';

/// Plays the bundled start/end recording chimes. Kept on its own
/// AudioPlayer instance, separate from AudioPlaybackService's player, so a
/// chime can never collide with an in-progress response/test playback.
class ChimePlayer {
  final AudioPlayer _player = AudioPlayer();
  bool _contextConfigured = false;

  /// Critical: by default, starting playback requests Android audio focus,
  /// which causes the ACTIVE microphone recording (VAD is still listening
  /// when the start chime plays) to lose focus and pause — meaning no more
  /// audio frames ever reach VAD, so onSpeechEnd never fires. Setting
  /// AndroidAudioFocus.none (and iOS's mixWithOthers) lets the chime play
  /// without interrupting the concurrent recording session at all.
  Future<void> _ensureAudioContext() async {
    if (_contextConfigured) return;
    await _player.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: {AVAudioSessionOptions.mixWithOthers},
        ),
      ),
    );
    _contextConfigured = true;
  }

  Future<void> playStart() => _play('sounds/chime_start.wav');
  Future<void> playEnd() => _play('sounds/chime_end.wav');

  Future<void> _play(String assetPath) async {
    await _ensureAudioContext();
    await _player.stop();
    await _player.play(AssetSource(assetPath));
  }

  void dispose() {
    _player.dispose();
  }
}