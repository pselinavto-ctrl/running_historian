import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:running_historian/config/constants.dart';
import 'package:running_historian/services/tts_service.dart';
import 'package:running_historian/domain/landmark.dart';

class FactsService {
  final TtsService tts;
  final Set<String> _shownPoiIds = {}; // ID показанных POI в этой сессии
  final Set<int> _shownFactIndices = {}; // Индексы показанных фактов в этой сессии

  FactsService(this.tts);

  // Проверка близости к POI
  Future<void> checkProximityToPoi(Position position) async {
    for (var landmark in kLandmarks) {
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        landmark.lat,
        landmark.lon,
      );

      // Если в радиусе 50 метров и ещё не показывали в этой сессии
      if (distance <= kPoiTriggerRadius && !_shownPoiIds.contains(landmark.id)) {
        _shownPoiIds.add(landmark.id);

        // Форматируем речь
        String fact = _formatPoiFact(landmark);
        await tts.speak(fact);

        // Можно добавить логику для добавления в статистику
        return; // Озвучиваем только один POI за раз
      }
    }
  }

  // Форматирование факта о POI
  String _formatPoiFact(Landmark landmark) {
    final intros = [
      "Справа от вас",
      "Обратите внимание",
      "Рядом с вами",
      "Прямо перед вами",
    ];

    final intro = intros[DateTime.now().millisecondsSinceEpoch % intros.length];
    return "$intro ${landmark.name}. ${landmark.fact}";
  }

  // Выбор общего факта (с фильтрацией уже показанных)
  String? getGeneralFact(List<int> alreadySpokenGlobal) {
    // Все возможные индексы
    final allIndices = List.generate(kGeneralFacts.length, (i) => i);

    // Фильтруем: убираем уже показанные в этой сессии И в глобальном банке
    final availableIndices = allIndices.where((index) {
      return !_shownFactIndices.contains(index) && !alreadySpokenGlobal.contains(index);
    }).toList();

    if (availableIndices.isEmpty) {
      // Если все факты уже использованы - разрешаем повтор
      return _getRandomFact();
    }

    // Выбираем случайный из доступных
    final randomIndex = availableIndices[math.Random().nextInt(availableIndices.length)];
    _shownFactIndices.add(randomIndex);

    return "Интересный факт о Ростове-на-Дону: ${kGeneralFacts[randomIndex]}";
  }

  // Запасной вариант: случайный факт (даже если уже был)
  String _getRandomFact() {
    final randomIndex = math.Random().nextInt(kGeneralFacts.length);
    return "Ещё один интересный факт: ${kGeneralFacts[randomIndex]}";
  }

  // Очистка состояния для новой тренировки
  void clearSessionState() {
    _shownPoiIds.clear();
    _shownFactIndices.clear();
  }

  // Получение показанных индексов для сохранения
  List<int> getSpokenIndices() {
    return _shownFactIndices.toList();
  }
}