import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:running_historian/config/constants.dart';
import 'package:running_historian/services/tts_service.dart';
import 'package:running_historian/domain/landmark.dart';

class FactsService {
  final TtsService tts;
  final List<String> _shownFacts = [];

  FactsService(this.tts);

  // Шаблоны речи
  final List<String> _intros = [
    "Знаете интересный момент:",
    "Мало кто знает, но",
    "Обратите внимание:",
    "Любопытный факт:",
  ];

  Future<void> checkProximityToPoi(Position position) async {
    for (var landmark in kLandmarks) {
      double distance = _calculateDistance(position, landmark);

      if (distance <= landmark.radius && !_shownFacts.contains(landmark.id)) {
        _shownFacts.add(landmark.id);

        String fact = await _getFactForLandmark(landmark, position);
        await tts.speak(fact);
      }
    }
  }

  double _calculateDistance(Position pos1, Landmark pos2) {
    const double earthRadius = 6371000;
    double dLat = (pos2.lat - pos1.latitude) * (math.pi / 180);
    double dLon = (pos2.lon - pos1.longitude) * (math.pi / 180);
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(pos1.latitude * (math.pi / 180)) *
            math.cos(pos2.lat * (math.pi / 180)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  Future<String> _getFactForLandmark(
      Landmark landmark, Position position) async {
    // Проверяем интернет
    bool hasInternet = await _hasInternet();

    if (hasInternet) {
      // Запрашиваем онлайн-факт из Wikipedia
      String onlineFact = await _fetchWikipediaFact(landmark);
      if (onlineFact.isNotEmpty) {
        return _humanizeFact(onlineFact);
      }
    }

    // Используем офлайн-факт
    return _humanizeFact(landmark.fact);
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await http
          .get(Uri.parse('https://httpbin.org/ip'))
          .timeout(Duration(seconds: 3));
      return result.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String> _fetchWikipediaFact(Landmark landmark) async {
    try {
      // Запрос к MediaWiki API
      final response = await http
          .get(
            Uri.parse(
                'https://ru.wikipedia.org/w/api.php?action=query&format=json&prop=extracts&exintro=1&explaintext=1&titles=${Uri.encodeComponent(landmark.name)}'),
          )
          .timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final pages = data['query']['pages'];
        final pageId = pages.keys.first;
        final extract = pages[pageId]['extract'] ?? '';

        // Очищаем текст
        return extract.split('.').first.trim();
      }
    } catch (e) {
      print('Ошибка получения факта из Wikipedia: $e');
    }
    return '';
  }

  String _humanizeFact(String fact) {
    // Выбираем случайную подводку
    String intro =
        _intros[DateTime.now().millisecondsSinceEpoch % _intros.length];

    // Собираем фразу
    return '$intro $fact';
  }
}
