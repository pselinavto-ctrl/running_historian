// lib/utils/kalman_filter.dart
import 'package:latlong2/latlong.dart';

/// Фильтр Калмана для сглаживания координат в городских условиях
/// Оптимизирован для точности 5-7 метров при ходьбе/беге
class KalmanLatLng {
  final double processNoise;
  final double measurementNoise;
  double _x = 0.0; // latitude
  double _y = 0.0; // longitude
  double _vx = 0.0;
  double _vy = 0.0;
  double _pxx = 1.0;
  double _pyy = 1.0;
  double _pxvx = 0.0;
  double _pyvy = 0.0;
  double _pvxvx = 1.0;
  double _pvyvy = 1.0;
  bool _initialized = false; // 🔑 КРИТИЧЕСКИ ВАЖНО: флаг инициализации

  KalmanLatLng(this.processNoise, this.measurementNoise);

  void reset() {
    _initialized = false;
    _x = 0.0;
    _y = 0.0;
    _vx = 0.0;
    _vy = 0.0;
    _pxx = 1.0;
    _pyy = 1.0;
    _pxvx = 0.0;
    _pyvy = 0.0;
    _pvxvx = 1.0;
    _pvyvy = 1.0;
  }

  LatLng process(LatLng measurement, double accuracy, double dt) {
    if (dt <= 0) dt = 0.1;

    // 🔑 ПРАВИЛЬНАЯ ИНИЦИАЛИЗАЦИЯ ПЕРВОЙ ТОЧКИ
    if (!_initialized) {
      _initialized = true;
      _x = measurement.latitude;
      _y = measurement.longitude;
      _pxx = accuracy * accuracy;
      _pyy = accuracy * accuracy;
      return LatLng(_x, _y);
    }

    // Предсказание
    _x += _vx * dt;
    _y += _vy * dt;
    _pxx += _pvxvx * dt * dt + 2 * _pxvx * dt + processNoise;
    _pyy += _pvyvy * dt * dt + 2 * _pyvy * dt + processNoise;
    _pxvx += _pvxvx * dt;
    _pyvy += _pvyvy * dt;

    // Обновление
    final r = accuracy * accuracy + measurementNoise;
    final kx = _pxx / (_pxx + r);
    final ky = _pyy / (_pyy + r);
    final kvx = _pxvx / (_pxx + r);
    final kvy = _pyvy / (_pyy + r);

    _x += kx * (measurement.latitude - _x);
    _y += ky * (measurement.longitude - _y);
    _vx += kvx * (measurement.latitude - _x);
    _vy += kvy * (measurement.longitude - _y);

    _pxx = (1 - kx) * _pxx;
    _pyy = (1 - ky) * _pyy;
    _pxvx = (1 - kvx) * _pxvx;
    _pyvy = (1 - kvy) * _pyvy;
    _pvxvx = (1 - kvx) * _pvxvx;
    _pvyvy = (1 - kvy) * _pvyvy;

    return LatLng(_x, _y);
  }
}