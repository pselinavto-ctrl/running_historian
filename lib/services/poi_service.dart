// lib/services/poi_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:running_historian/domain/poi.dart';

class PoiService {
  static const String _boxName = 'osm_poi';
  static const List<String> _osmTags = [
    'historic=monument',
    'tourism=museum',
    'tourism=attraction',
    'leisure=park',
    'amenity=theatre',
    'building=train_station',
    'amenity=university',
  ];

  late Box<Poi> _box;

  Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      _box = await Hive.openBox<Poi>(_boxName);
    } else {
      _box = Hive.box(_boxName);
    }
  }

  // Загрузка POI по bbox (широта/долгота)
  Future<void> loadPoiForBbox(double minLat, double maxLat, double minLon, double maxLon) async {
    // Очищаем старые POI
    await _box.clear();

    final query = '''
[out:json];
(
  ${_osmTags.map((tag) => 'node["$tag"]($minLat,$minLon,$maxLat,$maxLon);').join('\n')}
  ${_osmTags.map((tag) => 'way["$tag"]($minLat,$minLon,$maxLat,$maxLon);').join('\n')}
);
out center;
''';

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
        headers: {'Content-Type': 'text/plain'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List?;

        if (elements != null) {
          for (var el in elements) {
            final type = el['type'];
            final id = el['id'].toString();
            final tags = el['tags'] as Map<String, dynamic>?;

            if (tags == null) continue;

            final name = tags['name'] ?? tags['addr:street'] ?? 'Интересное место';
            double? lat, lon;

            if (type == 'node') {
              lat = el['lat'];
              lon = el['lon'];
            } else if (type == 'way' && el.containsKey('center')) {
              lat = el['center']['lat'];
              lon = el['center']['lon'];
            }

            if (lat != null && lon != null) {
              await _box.put(id, Poi(
                id: id,
                name: name,
                lat: lat,
                lon: lon,
                announced: false,
              ));
            }
          }
        }
      }
    } catch (e) {
      print('Ошибка загрузки POI: $e');
    }
  }

  // Проверка близости к POI
  Future<bool> checkNearbyPoi(double userLat, double userLon) async {
    for (final poi in _box.values) {
      if (poi.announced) continue;

      final distance = Geolocator.distanceBetween(userLat, userLon, poi.lat, poi.lon);
      if (distance <= 50) {
        poi.announced = true;
        await poi.save();
        return true; // сигнал: факт будет озвучен
      }
    }
    return false;
  }

  // Формирование речи
  String formatPoiFact(Poi poi) {
    final directions = ['Слева', 'Справа', 'Рядом', 'Прямо перед вами'];
    final dir = directions[DateTime.now().millisecondsSinceEpoch % directions.length];
    return '$dir — ${poi.name}.';
  }

  // Получение неозвученного POI (для TTS)
  Poi? getUnannouncedPoi(double userLat, double userLon) {
    for (final poi in _box.values) {
      if (!poi.announced) {
        final distance = Geolocator.distanceBetween(userLat, userLon, poi.lat, poi.lon);
        if (distance <= 50) {
          return poi;
        }
      }
    }
    return null;
  }

  // Сброс флага при новой тренировке
  Future<void> resetAnnouncedFlags() async {
    for (final poi in _box.values) {
      if (poi.announced) {
        poi.announced = false;
        await poi.save();
      }
    }
  }
}