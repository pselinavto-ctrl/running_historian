import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;

class LocationService {
  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    );
  }

  static double calculateDistance(Position pos1, Position pos2) {
    const double earthRadius = 6371000;
    double dLat = (pos2.latitude - pos1.latitude) * (math.pi / 180);
    double dLon = (pos2.longitude - pos1.longitude) * (math.pi / 180);
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(pos1.latitude * (math.pi / 180)) *
            math.cos(pos2.latitude * (math.pi / 180)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }
}