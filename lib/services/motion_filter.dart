// lib/services/motion_filter.dart

import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class MotionFilter {
  LatLng? _lastGps;
  LatLng? _visual;
  double _heading = 0;
  DateTime? _lastTime;

  /// Обновляет внутреннее состояние фильтра и возвращает визуальную позицию
  LatLng update(Position gps) {
    final now = DateTime.now();
    final gpsPoint = LatLng(gps.latitude, gps.longitude);

    if (_lastGps == null) {
      _lastGps = gpsPoint;
      _visual = gpsPoint;
      _lastTime = now;
      _heading = gps.heading;
      return gpsPoint;
    }

    final dt = now.difference(_lastTime!).inMilliseconds / 1000.0;
    final speed = math.max(gps.speed, 0.5);

    // 1️⃣ PREDICT (dead-reckoning)
    final predicted = _predict(_visual!, speed, _heading, dt);

    // 2️⃣ BLEND (смешивание предсказанного и нового GPS)
    final blended = LatLng(
      _lerp(predicted.latitude, gpsPoint.latitude, 0.25),
      _lerp(predicted.longitude, gpsPoint.longitude, 0.25),
    );

    // 3️⃣ SMOOTH HEADING
    _heading = _smoothAngle(_heading, gps.heading, 0.15);

    _visual = blended;
    _lastGps = gpsPoint;
    _lastTime = now;

    return blended;
  }

  /// Предсказывает позицию по текущей скорости и направлению
  LatLng _predict(LatLng p, double speed, double heading, double dt) {
    final meters = speed * dt;
    final dx = meters * math.cos(heading * math.pi / 180);
    final dy = meters * math.sin(heading * math.pi / 180);

    return LatLng(
      p.latitude + dy / 111111,
      p.longitude + dx / (111111 * math.cos(p.latitude * math.pi / 180)),
    );
  }

  /// Линейная интерполяция
  double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Плавное изменение угла (учитывает переход через 0/360)
  double _smoothAngle(double a, double b, double t) {
    var diff = (b - a + 180) % 360 - 180;
    return a + diff * t;
  }

  /// Возвращает текущее сглаженное направление
  double get heading => _heading;
}
