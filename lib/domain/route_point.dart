// lib/domain/route_point.dart

import 'package:hive/hive.dart';

part 'route_point.g.dart';

@HiveType(typeId: 2) // Убедитесь, что typeId уникален и не занят
class RoutePoint {
  @HiveField(0)
  final double lat;

  @HiveField(1)
  final double lon;

  @HiveField(2)
  final DateTime? timestamp;

  @HiveField(3)
  final double speed;

  RoutePoint({
    required this.lat,
    required this.lon,
    this.timestamp,
    required this.speed,
  });
}