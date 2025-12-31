import 'package:hive/hive.dart';
import 'package:geolocator/geolocator.dart';

part 'route_point.g.dart';

@HiveType(typeId: 1)
class RoutePoint {
  @HiveField(0)
  final double lat;

  @HiveField(1)
  final double lon;

  @HiveField(2)
  final DateTime timestamp;

  RoutePoint({
    required this.lat,
    required this.lon,
    required this.timestamp,
  });

  factory RoutePoint.fromPosition(Position position) {
    return RoutePoint(
      lat: position.latitude,
      lon: position.longitude,
      timestamp: position.timestamp ?? DateTime.now(),
    );
  }
}