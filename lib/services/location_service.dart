import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static Position? _lastPosition;

  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).transform(
      StreamTransformer.fromHandlers(
        handleData: (position, sink) {
          if (_isValid(position, _lastPosition)) {
            _lastPosition = position;
            sink.add(position);
          }
        },
      ),
    );
  }

  static bool _isValid(Position current, Position? last) {
    if (current.accuracy > 25) return false;
    if (current.speed > 10) return false;

    if (last != null) {
      final distance = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        current.latitude,
        current.longitude,
      );
      if (distance > 50) return false;
    }

    return true;
  }

  static void reset() {
    _lastPosition = null;
  }
}
