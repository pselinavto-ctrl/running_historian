import 'package:just_audio/just_audio.dart';

enum MusicMode { app, external }

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  MusicMode mode = MusicMode.external;
  double _savedVolume = 1.0;

  Future<void> playMusic(MusicMode mode) async {
    this.mode = mode;
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

  // 👇 НОВЫЙ МЕТОД: приглушить музыку для TTS
  Future<void> duckMusic() async {
    if (mode == MusicMode.app) {
      _savedVolume = _player.volume;
      await _player.setVolume(_savedVolume * 0.3); // Приглушаем до 30%
    }
  }

  // 👇 НОВЫЙ МЕТОД: восстановить громкость
  Future<void> restoreMusic() async {
    if (mode == MusicMode.app) {
      await _player.setVolume(_savedVolume);
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