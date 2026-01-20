import 'dart:collection';
import 'package:geolocator/geolocator.dart';
import 'package:collection/collection.dart';

/// Состояние гида
enum GuideState {
  idle, // Готов говорить
  speaking, // Говорит прямо сейчас
  cooldown, // Жёсткая пауза после речи
}

/// Тип речи
enum SpeechType { poi, context, general }

/// Элемент речи
class SpeechItem {
  final String text;
  final SpeechType type;
  final int priority; // 1–10
  final String? poiId;

  SpeechItem({
    required this.text,
    required this.type,
    required this.priority,
    this.poiId,
  });
}

/// ЯДРО СИСТЕМЫ ПРИНЯТИЯ РЕШЕНИЙ
class GuideDecisionEngine {
  // =====================
  // STATE
  // =====================
  GuideState _state = GuideState.idle;

  DateTime? _lastSpeechTime;
  Position? _lastSpeechPosition;

  double _distanceSinceLastSpeech = 0.0;
  double _previousPoiDistance = double.infinity;
  double _lastGeneralFactDistance = 0.0;

  // =====================
  // CONFIG
  // =====================
  static const Duration minCooldown = Duration(minutes: 1);
  static const Duration maxCooldown = Duration(minutes: 3);

  static const double minDistanceBetweenSpeeches = 300.0; // м
  static const double poiTriggerRadius = 80.0; // м

  // =====================
  // QUEUE
  // =====================
  final PriorityQueue<SpeechItem> _queue = PriorityQueue<SpeechItem>(
    (a, b) => b.priority.compareTo(a.priority),
  );

  // =====================
  // PUBLIC API
  // =====================

  GuideState get state => _state;

  /// Основной входной метод — вызывать на КАЖДОМ GPS апдейте
  void onLocationUpdate({
    required Position position,
    required double deltaDistanceMeters,
    double? nearestPoiDistance,
    String? nearestPoiId,
    bool isNearestPoiImportant = false,
  }) {
    _distanceSinceLastSpeech += deltaDistanceMeters;

    if (_state != GuideState.idle) return;

    // 1. POI имеет абсолютный приоритет
    if (isNearestPoiImportant &&
        nearestPoiDistance != null &&
        nearestPoiDistance <= poiTriggerRadius &&
        !_poiAlreadySpoken(nearestPoiId)) {
      // Проверяем, ПРИБЛИЖАЕМСЯ ли мы к POI
      if (_isApproachingPoi(nearestPoiDistance)) {
        _previousPoiDistance = nearestPoiDistance;
        return; // Пусть внешний код добавит речь в очередь
      }
    }

    // Безопасный сброс расстояния до POI
    if (nearestPoiDistance == null ||
        nearestPoiDistance > poiTriggerRadius * 1.5) {
      _previousPoiDistance = double.infinity;
    }

    // 2. Общие / контекстные факты — только если выполнены условия
    if (!_canSpeakByTime()) return;
    if (_distanceSinceLastSpeech < minDistanceBetweenSpeeches) return;
  }

  /// Можно ли сейчас произнести речь
  bool canDeliverSpeech() {
    return _state == GuideState.idle && _queue.isNotEmpty;
  }

  /// Забрать следующий элемент речи
  SpeechItem? takeNextSpeech() {
    if (!canDeliverSpeech()) return null;
    _state = GuideState.speaking; // ← Устанавливаем состояние
    return _queue.removeFirst();
  }

  /// ОБЯЗАТЕЛЬНО вызывать после завершения TTS
  void markSpeechDelivered(Position position, {String? poiId}) {
    _state = GuideState.cooldown;
    _lastSpeechTime = DateTime.now();
    _lastSpeechPosition = position;
    _distanceSinceLastSpeech = 0.0;

    if (poiId != null) {
      _spokenPoiIds.add(poiId);
    }

    final cooldown = _calculateCooldown();

    Future.delayed(cooldown, () {
      _state = GuideState.idle;
    });
  }

  /// Добавить речь в очередь
  void enqueueSpeech(SpeechItem item) {
    _queue.add(item);
  }

  /// Проверка для general фактов (внешний таймер/счётчик)
  bool shouldTryGeneralFact(double totalRunDistance) {
    if (totalRunDistance - _lastGeneralFactDistance < 500.0) return false;
    if (_distanceSinceLastSpeech < minDistanceBetweenSpeeches) return false;
    if (!_canSpeakByTime()) return false;

    _lastGeneralFactDistance = totalRunDistance;
    return true;
  }

  /// Очистка при старте новой тренировки
  void reset() {
    _state = GuideState.idle;
    _lastSpeechTime = null;
    _lastSpeechPosition = null;
    _distanceSinceLastSpeech = 0.0;
    _previousPoiDistance = double.infinity;
    _lastGeneralFactDistance = 0.0;
    _queue.clear();
    _spokenPoiIds.clear();
  }

  // =====================
  // INTERNAL LOGIC
  // =====================

  final Set<String> _spokenPoiIds = {};

  bool _poiAlreadySpoken(String? poiId) {
    if (poiId == null) return false;
    return _spokenPoiIds.contains(poiId);
  }

  bool _canSpeakByTime() {
    if (_lastSpeechTime == null) return true;

    final elapsed = DateTime.now().difference(_lastSpeechTime!);
    return elapsed >= minCooldown;
  }

  Duration _calculateCooldown() {
    if (_lastSpeechTime == null) return minCooldown;

    final minute = DateTime.now().minute;
    final range = maxCooldown.inMinutes - minCooldown.inMinutes;

    final dynamicMinutes = minCooldown.inMinutes + (minute % range);
    return Duration(minutes: dynamicMinutes);
  }

  bool _isApproachingPoi(double currentDistance) {
    if (_previousPoiDistance == double.infinity) {
      return true; // Первый замер
    }
    return currentDistance < _previousPoiDistance;
  }
}
