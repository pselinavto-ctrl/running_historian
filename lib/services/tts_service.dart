import 'package:flutter_tts/flutter_tts.dart';
import 'package:running_historian/services/audio_service.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  final AudioService audio;

  TtsService(this.audio);

  Future<void> init() async {
    await _tts.setLanguage('ru-RU');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> speak(String text) async {
    if (audio.mode == MusicMode.app) {
      await audio.setVolume(0.3);
    }

    await _tts.speak(text);

    if (audio.mode == MusicMode.app) {
      await audio.setVolume(1.0);
    }
  }

  void dispose() {
    _tts.stop();
  }
}