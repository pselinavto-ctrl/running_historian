import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:running_historian/services/location_service.dart';
import 'package:running_historian/domain/route_point.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/storage/run_repository.dart';
import 'package:running_historian/ui/widgets/run_controls.dart';
import 'package:running_historian/ui/widgets/distance_panel.dart';
import 'package:running_historian/config/constants.dart';
import 'package:running_historian/services/tts_service.dart';
import 'package:running_historian/services/audio_service.dart';
import 'package:running_historian/domain/landmark.dart';
import 'package:running_historian/ui/screens/history_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:running_historian/services/facts_service.dart';
import 'package:running_historian/ui/widgets/compass_marker.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:running_historian/services/background_service.dart';
import 'dart:math' as math;

class RunScreen extends StatefulWidget {
  const RunScreen({super.key});

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  StreamSubscription<Position>? _locationSubscription;
  Timer? _factsTimer;
  bool _isRunning = false;
  bool _showResults = false;
  final AudioService _audio = AudioService();
  late final TtsService _tts;
  late final FactsService _factsService;
  List<RoutePoint> _route = [];
  DateTime? _runStartTime;
  DateTime? _runEndTime;
  int _factsCount = 0; // 👈 Счётчик фактов
  double _distance = 0.0; // 👈 Расстояние в км
  double _totalDistanceInMeters = 0.0; // 👈 Расстояние в метрах (для точности)
  List<RunSession> _history = [];
  MusicMode _musicMode = MusicMode.external;
  DateTime? _lastFactTime;
  bool _isPaused = false;
  double _heading = 0.0; // Направление движения

  // 👇 НОВОЕ: список сказанных индексов (локально)
  final Set<int> _lastFactIndices = <int>{};

  // 👇 НОВОЕ: время последнего движения камеры
  DateTime? _lastCameraMove;

  // 👇 НОВОЕ: буфер сглаживания
  final List<RoutePoint> _smoothBuffer = [];

  // Анимации
  late AnimationController _distanceController;
  late Animation<double> _distanceAnimation;
  late AnimationController _factController;
  late Animation<double> _factAnimation;

  @override
  void initState() {
    super.initState();
    _tts = TtsService(_audio)..init();
    _factsService = FactsService(_tts);
    _initAnimations();
    _loadHistory();
    _initLocation(); // Инициализация геолокации при старте экрана
  }

  void _initAnimations() {
    _distanceController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _distanceAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(_distanceController);

    _factController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _factAnimation = Tween<double>(begin: 0, end: 1).animate(_factController);
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _factsTimer?.cancel();
    _distanceController.dispose();
    _factController.dispose();
    _tts.dispose();
    _audio.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    _history = await RunRepository().getHistory();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initLocation() async {
    // 1. Проверяем включена ли геолокация вообще
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings(); // 👈 НАТИВНО
      return;
    }

    // 2. Проверяем разрешения
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _showError('Без геолокации приложение не работает');
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      _showError('Разрешите геолокацию в настройках');
      return;
    }

    // 3. ПОЛУЧАЕМ ТЕКУЩУЮ ПОЗИЦИЮ (КРИТИЧНО)
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    if (!mounted) return;

    setState(() {
      _currentPosition = position;
    });

    // 4. СРАЗИУ ЦЕНТРИРУЕМ КАРТУ
    _mapController.move(LatLng(position.latitude, position.longitude), 15);

    // 5. СТАРТУЕМ STREAM
    _startLocationUpdates();
  }

  void _showError(String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Геолокация'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  void _startLocationUpdates() {
    _locationSubscription?.cancel();
    _locationSubscription = LocationService.getPositionStream().listen((
      position,
    ) {
      if (!mounted) return;

      setState(() {
        _currentPosition = position;
        // 👇 ИСПРАВЛЕНО: дёргание компаса при низкой скорости
        _heading = position.speed > 0.5 ? position.heading : _heading;

        if (_isRunning && !_isPaused) {
          // 👇 ИСПРАВЛЕНО: дублирующийся RoutePoint при стоянии
          if (_route.isNotEmpty) {
            final last = _route.last;
            final dist = Geolocator.distanceBetween(
              last.lat,
              last.lon,
              position.latitude,
              position.longitude,
            );
            if (dist < 3) return;
          }

          // 👇 СГЛАЖИВАНИЕ КООРДИНАТ
          final smoothed = _getSmoothedPoint(RoutePoint.fromPosition(position));
          _route.add(
            RoutePoint(
              lat: smoothed.latitude,
              lon: smoothed.longitude,
              timestamp: position.timestamp,
              speed: position.speed ?? 0.0,
            ),
          );

          _calculateDistance();
          _checkProximity(position);
        }
      });

      // 👇 ПЛАВНОЕ ДВИЖЕНИЕ КАМЕРЫ (смещение вперёд)
      _moveCamera(position);
    });
  }

  // 👇 НОВОЕ: сглаживание координат
  LatLng _getSmoothedPoint(RoutePoint point) {
    _smoothBuffer.add(point);
    if (_smoothBuffer.length > 5) {
      _smoothBuffer.removeAt(0);
    }

    final lat =
        _smoothBuffer.map((p) => p.lat).reduce((a, b) => a + b) /
        _smoothBuffer.length;
    final lon =
        _smoothBuffer.map((p) => p.lon).reduce((a, b) => a + b) /
        _smoothBuffer.length;

    return LatLng(lat, lon);
  }

  void _moveCamera(Position position) {
    final now = DateTime.now();
    if (_lastCameraMove == null ||
        now.difference(_lastCameraMove!) > const Duration(seconds: 3)) {
      // 👇 СМЕЩЕНИЕ КАМЕРЫ ВПЕРЁД ПО НАПРАВЛЕНИЮ
      final offset = 0.0003;
      final target = LatLng(
        position.latitude + offset * math.cos(_heading * math.pi / 180),
        position.longitude + offset * math.sin(_heading * math.pi / 180),
      );

      _mapController.move(target, 17);
      _lastCameraMove = now;
    }
  }

  void _calculateDistance() {
    if (_route.length < 2) return;

    double lastDistance = 0.0;
    if (_route.length >= 2) {
      final pos1 = _route[_route.length - 2];
      final pos2 = _route[_route.length - 1];
      // 👇 ИСПОЛЬЗУЕМ Geolocator.distanceBetween
      lastDistance = Geolocator.distanceBetween(
        pos1.lat,
        pos1.lon,
        pos2.lat,
        pos2.lon,
      );
    }

    // 👇 СЧИТАЕМ В МЕТРАХ ДЛЯ ТОЧНОСТИ
    setState(() {
      _totalDistanceInMeters += lastDistance;
      _distance = _totalDistanceInMeters / 1000;
    });
    _distanceController.reset();
    _distanceController.forward();
  }

  void _checkProximity(Position position) {
    _factsService.checkProximityToPoi(position); // 👈 Вызываем проверку
  }

  void _startGeneralFacts() {
    _factsTimer?.cancel();
    _factsTimer = Timer.periodic(Duration(minutes: kFactsIntervalMinutes), (
      timer,
    ) {
      if (_isRunning && !_isPaused && _route.length > 5) {
        final now = DateTime.now();
        if (_lastFactTime == null ||
            now.difference(_lastFactTime!) >=
                Duration(minutes: kMinIntervalBetweenFacts)) {
          _lastFactTime = now;

          // 👇 ПОЛУЧАЕМ ВСЕ СКАЗАННЫЕ ИНДЕКСЫ (из прошлых сессий)
          final allSpokenIndices = RunRepository().getAllSpokenFactIndices();

          // ИЩЕМ НЕСКАЗАННЫЙ ФАКТ
          final availableIndices = <int>[];
          for (int i = 0; i < kGeneralFacts.length; i++) {
            if (!allSpokenIndices.contains(i)) {
              availableIndices.add(i);
            }
          }

          int? randomIndex;
          if (availableIndices.isNotEmpty) {
            // 👇 БЕРЕМ СЛУЧАЙНЫЙ ИЗ ОСТАВШИХСЯ
            randomIndex =
                availableIndices[DateTime.now().millisecondsSinceEpoch %
                    availableIndices.length];
          } else {
            // 👇 ЕСЛИ ВСЕ СКАЗАНЫ — БЕРЕМ СЛУЧАЙНЫЙ (начинаем сначала)
            randomIndex =
                DateTime.now().millisecondsSinceEpoch % kGeneralFacts.length;
          }

          _tts.speak(
            "Интересный факт о Ростове-на-Дону: ${kGeneralFacts[randomIndex]}",
          );

          // 👇 УВЕЛИЧИВАЕМ СЧЁТЧИК ФАКТОВ
          setState(() {
            _factsCount++;
          });

          // 👇 СОХРАНЯЕМ ИНДЕКС В ЛОКАЛЬНЫЙ СПИСОК (для текущей пробежки)
          if (randomIndex != null) {
            _lastFactIndices.add(randomIndex);
          }
        }
      }
    });
  }

  // 👇 НОВОЕ: голосовая подсказка для кнопок
  void _speakButtonAction(String text) {
    _tts.speak(text);
  }

  void _startRun() async {
    await initBackgroundService(); // 👈 Запускаем фоновый сервис при старте бега
    FlutterBackgroundService().startService();

    if (mounted) {
      setState(() {
        _isRunning = true;
        _showResults = false;
        _runStartTime = DateTime.now();
        _route = [];
        _factsCount = 0; // 👈 СБРОС СЧЁТЧИКА
        _distance = 0.0;
        _totalDistanceInMeters = 0.0; // 👈 СБРОС РАССТОЯНИЯ
        _lastFactTime = null;
        _isPaused = false;
        // 👇 ОЧИЩАЕМ список индексов
        _lastFactIndices.clear();
        // 👇 СБРОС ВРЕМЕНИ КАМЕРЫ
        _lastCameraMove = null;
        // 👇 СБРОС БУФЕРА СГЛАЖИВАНИЯ
        _smoothBuffer.clear();
      });
    }

    _startLocationUpdates();
    _audio.playMusic(_musicMode);
    _startGeneralFacts();

    // 👇 ГОЛОСОВАЯ ПОДСКАЗКА
    _speakButtonAction("Тренировка началась");
  }

  void _stopRun() {
    FlutterBackgroundService().invoke(
      'stopService',
    ); // 👈 Останавливаем фоновый сервис

    if (mounted) {
      setState(() {
        _isRunning = false;
        _showResults = true;
        _runEndTime = DateTime.now();
      });
    }
    _locationSubscription?.cancel();
    _audio.stopMusic();
    _factsTimer?.cancel();
    _saveRunSession();

    // 👇 ГОЛОСОВАЯ ПОДСКАЗКА
    _speakButtonAction("Тренировка окончена");
  }

  void _pauseRun() {
    if (mounted) {
      setState(() {
        _isPaused = true;
      });
    }

    // 👇 ГОЛОСОВАЯ ПОДСКАЗКА
    _speakButtonAction("Тренировка на паузе");
  }

  void _resumeRun() {
    if (mounted) {
      setState(() {
        _isPaused = false;
      });
    }

    // 👇 ГОЛОСОВАЯ ПОДСКАЗКА
    _speakButtonAction("Тренировка продолжается");
  }

  Future<void> _saveRunSession() async {
    // 👇 СОХРАНЯЕМ ТЕКУЩИЕ ИНДЕКСЫ В СЕССИЮ (не добавляем к истории)
    final session = RunSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      distance: _distance,
      duration: _runEndTime!.difference(_runStartTime!).inSeconds,
      factsCount: _factsCount,
      route: _route, // 👈 Сохраняем оригинальный маршрут с скоростью
      spokenFactIndices: _lastFactIndices
          .toList(), // 👈 Сохраняем локальные индексы
    );

    await RunRepository().saveSession(session);

    if (mounted) {
      setState(() {
        _history.add(session);
      });
    }

    print("💾 Сессия сохранена: $_distance км, $_factsCount фактов");
  }

  // 👇 НОВОЕ: градиентный трек
  List<Polyline> _buildSpeedPolylines() {
    final polylines = <Polyline>[];

    for (int i = 1; i < _route.length; i++) {
      final p1 = _route[i - 1];
      final p2 = _route[i];

      Color color;
      if (p1.speed < 2) {
        color = Colors.blue;
      } else if (p1.speed < 5) {
        color = const Color(0xFF9C27B0); // фиолетовый
      } else {
        color = Colors.red;
      }

      polylines.add(
        Polyline(
          points: [LatLng(p1.lat, p1.lon), LatLng(p2.lat, p2.lon)],
          strokeWidth: 5,
          color: color,
        ),
      );
    }

    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    if (_showResults) {
      return Scaffold(
        appBar: AppBar(title: const Text('Результаты')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Дистанция: ${_distance.toStringAsFixed(2)} км'),
              Text('Факты: $_factsCount'), // 👈 СЕЙЧАС УВЕЛИЧИВАЕТСЯ
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _showResults = false; // Возвращаемся к карте
                  });
                  _startRun(); // 👈 Начинаем новую тренировку
                },
                child: const Text('Новая тренировка'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ростов-на-Дону'),
        actions: [
          IconButton(
            icon: Icon(
              _musicMode == MusicMode.app
                  ? Icons.music_note
                  : Icons.library_music,
            ),
            onPressed: () {
              setState(() {
                _musicMode = _musicMode == MusicMode.app
                    ? MusicMode.external
                    : MusicMode.app;
              });
              _audio.playMusic(_musicMode);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (String choice) {
              if (choice == 'history') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HistoryScreen(history: _history),
                  ),
                );
              }
            },
            itemBuilder: (BuildContext context) {
              return {'history': 'История пробежек'}.entries.map((entry) {
                return PopupMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition != null
                  ? LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    )
                  : const LatLng(47.2313, 39.7233),
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png', // 👈 ОРИГИНАЛЬНЫЕ ТАЙЛЫ
                userAgentPackageName: 'com.example.running_historian',
              ),
              if (_route.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    // 👇 ГРАДИЕНТНЫЙ ТРЕК
                    ..._buildSpeedPolylines(),
                  ],
                ),
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      width: 50,
                      height: 50,
                      child: Transform.rotate(
                        angle: _heading * math.pi / 180, // 👈 НАПРАВЛЕНИЕ
                        child: Icon(
                          Icons.navigation,
                          color: Colors.deepPurple,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
              if (_route.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_route.first.lat, _route.first.lon),
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.fiber_manual_record,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                    // 👇 МАРКЕР ФИНИША
                    Marker(
                      point: LatLng(_route.last.lat, _route.last.lon),
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.flag,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: kLandmarks.map((landmark) {
                  return Marker(
                    point: LatLng(landmark.lat, landmark.lon),
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          DistancePanel(distance: _distance),
          RunControls(
            isRunning: _isRunning,
            isPaused: _isPaused,
            onStart: _startRun,
            onPause: _pauseRun,
            onResume: _resumeRun,
            onStop: _stopRun,
          ),
        ],
      ),
    );
  }
}
