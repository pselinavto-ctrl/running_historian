// lib/tracking/tracking_controller.dart

import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../domain/route_point.dart';

class TrackingState {
  final LatLng? position;
  final double distance; // в километрах
  final List<RoutePoint> route;

  TrackingState(this.position, this.distance, this.route);
}

class TrackingController {
  final LocationService locationService;

  final _state = StreamController<TrackingState>.broadcast();
  Stream<TrackingState> get stream => _state.stream;

  Position? _last;
  double _distance = 0;
  final _route = <RoutePoint>[];

  StreamSubscription? _sub;

  TrackingController(this.locationService);

  void start() {
    _sub = locationService.stream.listen(_onPosition);
  }

  void stop() {
    _sub?.cancel();
  }

  void _onPosition(Position pos) {
    if (_last != null) {
      _distance += Geolocator.distanceBetween(
        _last!.latitude,
        _last!.longitude,
        pos.latitude,
        pos.longitude,
      );
    }

    _last = pos;

    _route.add(RoutePoint(
      lat: pos.latitude,
      lon: pos.longitude,
      timestamp: DateTime.now(),
      speed: pos.speed,
    ));

    _state.add(
      TrackingState(
        LatLng(pos.latitude, pos.longitude),
        _distance / 1000, // в километрах
        List.from(_route),
      ),
    );
  }
}