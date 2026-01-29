// lib/utils/kalman_filter.dart
import 'dart:math';
import 'package:latlong2/latlong.dart';

/// Улучшенный адаптивный фильтр Калмана для GPS трекинга
/// Особенности:
/// - Автоматическая настройка параметров по скорости
/// - Учет широты для точной конвертации метров в градусы
/// - Предотвращение срезания углов
class AdaptiveKalmanFilter {
  // Параметры фильтра
  double _processNoise;
  double _measurementNoise;
  final double _minAccuracyMeters;
  final double _maxAccuracyMeters;
  
  // Состояние: [lat, lon, v_lat, v_lon] в градусах/сек
  List<double> _state = [0, 0, 0, 0];
  
  // Ковариационная матрица P (4x4 упрощенная)
  double _pLat = 1.0;
  double _pLon = 1.0;
  double _pVLat = 1.0;
  double _pVLon = 1.0;
  double _pLatVLat = 0.0;
  double _pLonVLon = 0.0;
  double _pLatLon = 0.0;  // Ковариация lat-lon для углов
  
  // Состояние фильтра
  bool _initialized = false;
  DateTime? _lastUpdateTime;
  LatLng? _lastPosition;
  
  // Статистика для адаптации
  double _avgSpeed = 0.0;
  List<double> _recentSpeeds = [];
  static const int _speedWindow = 10;
  
  // Константы
  static const double _earthRadiusM = 6371000.0;
  static const double _metersPerDegreeLat = 111000.0;
  static const double _maxSpeedForWalking = 2.5; // м/с
  static const double _maxSpeedForRunning = 6.0; // м/с
  
  AdaptiveKalmanFilter({
    double initialProcessNoise = 0.001,
    double initialMeasurementNoise = 0.01,
    double minAccuracyMeters = 3.0,
    double maxAccuracyMeters = 100.0,
  }) : 
    _processNoise = initialProcessNoise,
    _measurementNoise = initialMeasurementNoise,
    _minAccuracyMeters = minAccuracyMeters,
    _maxAccuracyMeters = maxAccuracyMeters;
  
  /// Сброс фильтра (только при новой сессии)
  void reset() {
    _initialized = false;
    _state = [0, 0, 0, 0];
    _pLat = 1.0;
    _pLon = 1.0;
    _pVLat = 1.0;
    _pVLon = 1.0;
    _pLatVLat = 0.0;
    _pLonVLon = 0.0;
    _pLatLon = 0.0;
    _lastUpdateTime = null;
    _lastPosition = null;
    _recentSpeeds.clear();
    _avgSpeed = 0.0;
  }
  
  /// Конвертация метров в градусы с учетом широты
  double _metersToDegreesLat(double meters) {
    return meters / _metersPerDegreeLat;
  }
  
  double _metersToDegreesLon(double meters, double lat) {
    final latRad = lat * pi / 180.0;
    final metersPerDegreeLon = _metersPerDegreeLat * cos(latRad);
    return meters / metersPerDegreeLon;
  }
  
  /// Расчет скорости между точками (БЕЗ ЗАВИСИМОСТИ ОТ GEOLOCATOR)
  double _calculateSpeed(LatLng p1, LatLng p2, double dt) {
    if (dt <= 0) return 0.0;
    
    // Упрощенный расчет расстояния в метрах для небольших дистанций
    final dLatMeters = (p2.latitude - p1.latitude) * _metersPerDegreeLat;
    final dLonMeters = (p2.longitude - p1.longitude) * _metersPerDegreeLat * 
        cos(p1.latitude * pi / 180.0);
    
    final distanceMeters = sqrt(dLatMeters * dLatMeters + dLonMeters * dLonMeters);
    return distanceMeters / dt;
  }
  
  /// Адаптация параметров по скорости
  void _adaptParameters(double speedMps) {
    // Обновляем окно скоростей
    _recentSpeeds.add(speedMps);
    if (_recentSpeeds.length > _speedWindow) {
      _recentSpeeds.removeAt(0);
    }
    
    // Средняя скорость
    _avgSpeed = _recentSpeeds.isEmpty ? 0.0 : 
        _recentSpeeds.reduce((a, b) => a + b) / _recentSpeeds.length;
    
    // Адаптация processNoise по скорости
    if (_avgSpeed < _maxSpeedForWalking) {
      // Ходьба - высокая точность, низкий шум
      _processNoise = 0.0001;
    } else if (_avgSpeed < _maxSpeedForRunning) {
      // Бег - средний шум
      _processNoise = 0.001;
    } else {
      // Быстрый бег - больше шума
      _processNoise = 0.01;
    }
    
    // Адаптация корреляции lat-lon по поворотам
    // Если скорость меняется быстро - вероятен поворот
    if (_recentSpeeds.length >= 3) {
      final speedChange = (_recentSpeeds.last - _recentSpeeds.first).abs();
      if (speedChange > 1.0) { // Резкое изменение скорости
        _pLatLon = 0.8; // Увеличиваем корреляцию для сохранения углов
      } else {
        _pLatLon = 0.3; // Нормальная корреляция
      }
    }
  }
  
  /// Основной метод обработки точки
  LatLng process(LatLng measurement, double accuracyMeters, [double dt = -1]) {
    final now = DateTime.now();
    
    // Автоматический расчет dt
    if (dt <= 0) {
      dt = _lastUpdateTime == null ? 1.0 : 
          now.difference(_lastUpdateTime!).inMilliseconds / 1000.0;
    }
    
    // Ограничиваем dt
    dt = dt.clamp(0.1, 10.0);
    
    // Конвертируем точность в градусы
    final accuracyLat = _metersToDegreesLat(
      accuracyMeters.clamp(_minAccuracyMeters, _maxAccuracyMeters)
    );
    final accuracyLon = _metersToDegreesLon(
      accuracyMeters.clamp(_minAccuracyMeters, _maxAccuracyMeters),
      measurement.latitude
    );
    
    // 🔑 ИНИЦИАЛИЗАЦИЯ С УЧЕТОМ СКОРОСТИ
    if (!_initialized) {
      _initialized = true;
      _state[0] = measurement.latitude;
      _state[1] = measurement.longitude;
      _state[2] = 0.0;
      _state[3] = 0.0;
      
      // Начальная неопределенность на основе точности GPS
      _pLat = accuracyLat * accuracyLat;
      _pLon = accuracyLon * accuracyLon;
      _pVLat = 0.1; // Небольшая начальная неопределенность скорости
      _pVLon = 0.1;
      _pLatLon = 0.2 * accuracyLat * accuracyLon; // Умеренная корреляция
      
      _lastUpdateTime = now;
      _lastPosition = measurement;
      
      return measurement;
    }
    
    // Расчет скорости для адаптации
    final currentSpeed = _lastPosition != null ? 
        _calculateSpeed(_lastPosition!, measurement, dt) : 0.0;
    _adaptParameters(currentSpeed);
    
    // 1. ПРЕДСКАЗАНИЕ
    final dt2 = dt * dt;
    
    // Обновляем позицию
    _state[0] += _state[2] * dt; // lat += v_lat * dt
    _state[1] += _state[3] * dt; // lon += v_lon * dt
    
    // Обновляем ковариацию с адаптивным processNoise
    _pLat += (2 * _pLatVLat + _pVLat * dt) * dt + _processNoise;
    _pLon += (2 * _pLonVLon + _pVLon * dt) * dt + _processNoise;
    _pLatVLat += _pVLat * dt;
    _pLonVLon += _pVLon * dt;
    
    // Корреляция для сохранения углов
    _pLatLon = _pLatLon * 0.9 + _processNoise * 0.1;
    
    // 2. ОБНОВЛЕНИЕ
    final rLat = accuracyLat * accuracyLat + _measurementNoise;
    final rLon = accuracyLon * accuracyLon + _measurementNoise;
    
    // Коэффициенты Калмана
    final kLat = _pLat / (_pLat + rLat);
    final kLon = _pLon / (_pLon + rLon);
    final kLatVLat = _pLatVLat / (_pLat + rLat);
    final kLonVLon = _pLonVLon / (_pLon + rLon);
    
    // Ошибки
    final latError = measurement.latitude - _state[0];
    final lonError = measurement.longitude - _state[1];
    
    // Обновление состояния
    _state[0] += kLat * latError;
    _state[1] += kLon * lonError;
    _state[2] += kLatVLat * latError;
    _state[3] += kLonVLon * lonError;
    
    // Обновление ковариации
    _pLat = (1 - kLat) * _pLat;
    _pLon = (1 - kLon) * _pLon;
    _pLatVLat = (1 - kLatVLat) * _pLatVLat;
    _pLonVLon = (1 - kLonVLon) * _pLonVLon;
    _pVLat = (1 - kLatVLat) * _pVLat;
    _pVLon = (1 - kLonVLon) * _pVLon;
    
    // Сохраняем корреляцию для следующих итераций
    _pLatLon = (1 - (kLat + kLon) * 0.5) * _pLatLon;
    
    _lastUpdateTime = now;
    _lastPosition = LatLng(_state[0], _state[1]);
    
    return _lastPosition!;
  }
  
  /// Получение текущей скорости (м/с)
  double getCurrentSpeed() {
    final vLatMs = _state[2] * _metersPerDegreeLat;
    final vLonMs = _state[3] * _metersPerDegreeLat * 
        cos(_state[0] * pi / 180.0);
    return sqrt(vLatMs * vLatMs + vLonMs * vLonMs);
  }
  
  /// Получение текущего курса (градусы)
  double getCurrentHeading() {
    final vLatMs = _state[2] * _metersPerDegreeLat;
    final vLonMs = _state[3] * _metersPerDegreeLat * 
        cos(_state[0] * pi / 180.0);
    
    if (vLatMs.abs() < 0.01 && vLonMs.abs() < 0.01) {
      return 0.0;
    }
    
    final headingRad = atan2(vLonMs, vLatMs);
    return headingRad * 180.0 / pi;
  }
  
  /// Получение доверительного интервала (метры)
  double getConfidenceRadius() {
    final stdLat = sqrt(_pLat) * _metersPerDegreeLat;
    final stdLon = sqrt(_pLon) * _metersPerDegreeLat * 
        cos(_state[0] * pi / 180.0);
    return sqrt(stdLat * stdLat + stdLon * stdLon);
  }
}