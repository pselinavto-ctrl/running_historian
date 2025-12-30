import 'package:just_audio/just_audio.dart';

enum MusicMode { app, external }

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  MusicMode mode = MusicMode.external;

  Future<void> playMusic(MusicMode mode) async {
    if (mode == MusicMode.external) return;
    await _player.setAsset('assets/music.mp3');
    await _player.setVolume(1);
    await _player.play();
  }

  Future<void> setVolume(double volume) async {
    if (mode == MusicMode.app) {
      await _player.setVolume(volume);
    }
  }

  void stopMusic() {
    if (mode == MusicMode.app) {
      _player.stop();
    }
  }

  void dispose() {
    _player.dispose();
  }
}