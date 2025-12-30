import 'package:geolocator/geolocator.dart';

class RoutePoint {
  final double lat;
  final double lon;
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

  Position toPosition() {
    return Position(
      latitude: lat,
      longitude: lon,
      timestamp: timestamp,
      accuracy: 10.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lon': lon,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      lat: json['lat'].toDouble(),
      lon: json['lon'].toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}