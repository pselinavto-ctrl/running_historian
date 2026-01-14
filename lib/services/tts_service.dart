import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:running_historian/services/audio_service.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  final AudioService _audio;
  
  // 👇 НОВЫЕ ПОЛЯ ДЛЯ СОСТОЯНИЯ
  bool _isSpeaking = false;
  bool _isPaused = false;
  
  TtsService(this._audio);

  Future<void> init() async {
    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.4);
    
    // 👇 НАСТРОЙКА ОБРАБОТЧИКОВ СОСТОЯНИЯ
    _tts.setStartHandler(() {
      _isSpeaking = true;
      _isPaused = false;
      _audio.duckMusic(); // Приглушаем музыку при начале речи
    });
    
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _isPaused = false;
      _audio.restoreMusic(); // Восстанавливаем музыку
    });
    
    _tts.setErrorHandler((error) {
      _isSpeaking = false;
      _isPaused = false;
      print('TTS Error: $error');
    });
  }

  // 👇 ГЕТТЕРЫ ДЛЯ ВИДЖЕТА
  bool get isSpeaking => _isSpeaking;
  bool get isPaused => _isPaused;

  Future<void> speak(String text) async {
    if (_isPaused) {
      // 👇 РАБОЧИЙ ВАРИАНТ: используем callMethod или stop/start
      await _tts.stop();
      await _tts.speak(text);
      _isPaused = false;
      _isSpeaking = true;
      _audio.duckMusic();
    } else {
      await _tts.speak(text);
    }
  }

  Future<void> pause() async {
    if (_isSpeaking && !_isPaused) {
      await _tts.pause();
      _isPaused = true;
      _audio.restoreMusic();
    }
  }

  Future<void> resume() async {
    if (_isPaused) {
      // 👇 ВАРИАНТ БЕЗ continue: начинаем заново
      _isPaused = false;
      _isSpeaking = false;
      // Не можем продолжить, поэтому просто сбрасываем состояние
      // Можно добавить логику для повторения последней фразы
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
    _isPaused = false;
    _audio.restoreMusic();
  }

  // 👇 Метод для фонового режима
  void listenToBackgroundCommands() {
    _tts.setStartHandler(() {
      print('📢 Говорим: фоновый режим');
    });
  }

  void dispose() {
    _tts.stop();
  }
}