// lib/services/location_service.dart

import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationService {
  final _controller = StreamController<Position>.broadcast();

  Stream<Position> get stream => _controller.stream;

  StreamSubscription? _sub;

  Future<void> start() async {
    final settings = const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
      _controller.add(pos);
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}