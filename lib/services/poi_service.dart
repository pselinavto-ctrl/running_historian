// lib/services/poi_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:running_historian/domain/poi.dart';

class PoiService {
  static const String _boxName = 'osm_poi';
  late Box<Poi> _box;

  Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      _box = await Hive.openBox<Poi>(_boxName);
    } else {
      _box = Hive.box(_boxName);
    }
  }

  Future<void> loadPoiForBbox(double minLat, double maxLat, double minLon, double maxLon) async {
    await _box.clear();
    final tags = [
      'node["historic"="monument"]',
      'node["tourism"="museum"]',
      'node["tourism"="attraction"]',
      'way["leisure"="park"]',
      'node["amenity"="theatre"]',
      'node["building"="train_station"]',
    ];
    final query = '''
[out:json];
(
  ${tags.map((t) => '$t($minLat,$minLon,$maxLat,$maxLon);').join('\n')}
);
out center;
''';
    try {
      // 🔑 УБРАН ЛИШНИЙ ПРОБЕЛ В URL (было '...interpreter  ')
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
              await _box.put(id, Poi(id: id, name: name, lat: lat, lon: lon));
            }
          }
        }
      } else {
        print('POI загрузка: статус ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка загрузки POI: $e');
    }
  }

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

  Future<void> resetAnnouncedFlags() async {
    for (final poi in _box.values) {
      if (poi.announced) {
        poi.announced = false;
        await poi.save();
      }
    }
  }

  String formatPoiFact(Poi poi) {
    final directions = ['Слева', 'Справа', 'Рядом', 'Прямо перед вами'];
    final dir = directions[DateTime.now().millisecondsSinceEpoch % directions.length];
    return '$dir — ${poi.name}.';
  }
}