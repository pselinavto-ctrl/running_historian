import 'package:hive/hive.dart';
import 'package:geolocator/geolocator.dart'; // 👈 Добавьте импорт

part 'route_point.g.dart';

@HiveType(typeId: 2)
class RoutePoint extends HiveObject {
  @HiveField(0)
  final double lat;

  @HiveField(1)
  final double lon;

  @HiveField(2)
  final DateTime timestamp;

  // 👇 НОВОЕ: скорость
  @HiveField(3)
  final double speed;

  RoutePoint({
    required this.lat,
    required this.lon,
    required this.timestamp,
    this.speed = 0.0,
  });

  factory RoutePoint.fromPosition(Position position) {
    return RoutePoint(
      lat: position.latitude,
      lon: position.longitude,
      timestamp: position.timestamp ?? DateTime.now(),
      speed: position.speed ?? 0.0, // 👈 Сохраняем скорость
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lon': lon,
      'timestamp': timestamp.toIso8601String(),
      'speed': speed,
    };
  }

  static RoutePoint fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      lat: json['lat'] as double,
      lon: json['lon'] as double,
      timestamp: DateTime.parse(json['timestamp'] as String),
      speed: json['speed'] as double,
    );
  }
}
