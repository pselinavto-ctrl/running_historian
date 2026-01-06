import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:running_historian/services/audio_service.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  final AudioService _audio;

  TtsService(this._audio);

  Future<void> init() async {
    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.4);
  }

  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  // 👇 НОВОЕ: принимаем команды из фона
  void listenToBackgroundCommands() {
    _tts.setStartHandler(() {
      print('📢 Говорим: фоновый режим');
    });
  }

  void dispose() {
    _tts.stop();
  }
}