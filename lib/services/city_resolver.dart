// lib/services/city_resolver.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class CityResolver {
  static Future<String?> detectCity(double lat, double lon) async {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?'
      'format=json&'
      'lat=$lat&'
      'lon=$lon&'
      'zoom=10&'
      'addressdetails=1',
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'running_historian/1.0 (your@email.com)',
        },
      );

      if (response.statusCode != 200) {
        print('⚠️ Nominatim error: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);
      final address = data['address'] as Map<String, dynamic>?;

      // Порядок приоритета: город → посёлок → деревня → регион
      return address?['city'] ??
             address?['town'] ??
             address?['village'] ??
             address?['state'];
    } catch (e) {
      print('❌ Ошибка reverse geocoding: $e');
      return null;
    }
  }
}