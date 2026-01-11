import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:running_historian/domain/route_point.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/storage/run_repository.dart';
import 'package:running_historian/config/constants.dart';
import 'package:running_historian/services/tts_service.dart';
import 'package:running_historian/services/audio_service.dart';
import 'package:running_historian/domain/landmark.dart';
import 'package:running_historian/ui/screens/history_screen.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:running_historian/services/background_service.dart';
import 'package:running_historian/services/facts_service.dart';
import 'package:running_historian/ui/screens/session_detail_screen.dart';
import 'package:permission_handler/permission_handler.dart';

// Стейт-машина
enum RunState {
  init,
  searchingGps,
  ready,
  countdown,
  running,
  paused,
  finished,
}

class RunScreen extends StatefulWidget {
  const RunScreen({super.key});

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  StreamSubscription? _backgroundLocationSubscription;
  Timer? _factsTimer;
  Timer? _runTicker;
  Duration _elapsedRunTime = Duration.zero;
  final AudioService _audio = AudioService();
  late final TtsService _tts;
  late final FactsService _factsService;
  List<RoutePoint> _route = []; // Теперь это восстановленный маршрут
  DateTime? _runStartTime;
  RunSession? _currentSession;
  int _factsCount = 0;
  double _distance = 0.0;
  double _totalDistanceInMeters = 0.0;
  List<RunSession> _history = [];
  MusicMode _musicMode = MusicMode.external;
  DateTime? _lastFactTime;
  double _heading = 0.0; // Это будет raw heading до сглаживания
  LatLng? _startPoint;
  final Set<int> _lastFactIndices = <int>{};
  RunState _state = RunState.searchingGps;
  Timer? _countdownTimer;
  int _countdown = 3;
  late AnimationController _distanceController;
  late Animation<double> _distanceAnimation;
  late AnimationController _factController;
  late Animation<double> _factAnimation;

  // 👇 1️⃣ ДОБАВЬ ПОЛЯ (ОБЯЗАТЕЛЬНО)
  LatLng? _smoothedPosition;
  double _smoothedHeading = 0.0;

  DateTime? _lastCameraUpdate;
  DateTime? _lastValidGpsTime;

  static const double _maxJumpMeters = 40; // анти-телепортация
  static const Duration _cameraInterval = Duration(milliseconds: 400);

  // 1️⃣ FOLLOW MODE (новое поле)
  bool _followUser = true;

  // ❗️ИСПРАВЛЕНО: добавлено поле для кэширования индексов
  List<int>? _cachedAllSpokenIndices;

  @override
  void initState() {
    super.initState();
    _tts = TtsService(_audio)..init();
    _factsService = FactsService(_tts);
    _initAnimations();
    _loadHistory();
    _requestLocationPermissionAndStart();
    // 👇 ДОБАВИТЬ НАБЛЮДАТЕЛЬ ЖИЗНЕННОГО ЦИКЛА
    WidgetsBinding.instance.addObserver(this);
  }

  // Метод для запроса разрешений и запуска сервиса
  Future<void> _requestLocationPermissionAndStart() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showErrorAndReturn(
          'Служба геолокации отключена. Приложение не сможет отслеживать ваш маршрут.',
        );
        return;
      }
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      _showErrorAndReturn(
        'Разрешение на геолокацию отклонено навсегда. Пожалуйста, предоставьте его в настройках приложения.',
      );
      return;
    }

    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      _showErrorAndReturn(
        'Разрешение на геолокацию не предоставлено. Приложение не сможет отслеживать ваш маршрут.',
      );
      return;
    }

    // Запрос разрешения на уведомления (для Android 13+)
    var notificationPermission = await Permission.notification.status;
    if (notificationPermission.isDenied) {
      notificationPermission = await Permission.notification.request();
      if (notificationPermission.isDenied) {
        _showErrorAndReturn(
          'Для работы фонового сервиса требуется разрешение на уведомления.',
        );
        return;
      }
    }

    _startBackgroundService();
    _initBackgroundListener();
    _attemptToGetCurrentLocation();
  }

  void _startBackgroundService() async {
    await initBackgroundService();
    bool started = await FlutterBackgroundService().startService();
    print('SERVICE STARTED = $started');

    if (started) {
      final isRunning = await FlutterBackgroundService().isRunning();
      print('SERVICE RUNNING = $isRunning');
    } else {
      print('FAILED TO START SERVICE');
    }
  }

  void _initBackgroundListener() {
    _backgroundLocationSubscription = FlutterBackgroundService()
        .on(
          'locationUpdate',
        ) // ❗️Теперь фоновый сервис вызывает это событие, когда сохраняет точку в Hive
        .listen(_onBackgroundLocation);
    print('Подписка на фоновое обновление местоположения установлена');
  }

  Future<void> _attemptToGetCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            15,
          );
        });
      }
    } catch (e) {
      print('Не удалось получить текущую позицию: $e');
    }
  }

  void _showErrorAndReturn(String message) {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Геолокация'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
              child: const Text('ОК'),
            ),
          ],
        ),
      );
    }
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
    _backgroundLocationSubscription?.cancel();
    _factsTimer?.cancel();
    _runTicker?.cancel();
    _countdownTimer?.cancel();
    _distanceController.dispose();
    _factController.dispose();
    _tts.dispose();
    _audio.dispose();

    // 👇 УДАЛИТЬ НАБЛЮДАТЕЛЬ
    WidgetsBinding.instance.removeObserver(this);

    // ОСТАНОВИТЬ СЕРВИС ТОЛЬКО ПРИ УНИЧТОЖЕНИИ ВИДЖЕТА
    FlutterBackgroundService().invoke('stopService');

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restoreRouteFromBackground();
    }
  }

  Future<void> _loadHistory() async {
    _history = await RunRepository().getHistory();
    if (mounted) {
      setState(() {});
    }
  }

  // 👇 2️⃣ АНТИ-GPS СКАЧКИ (КРИТИЧНО)
  bool _isGpsJump(Position prev, Position next) {
    final d = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      next.latitude,
      next.longitude,
    );

    return d > _maxJumpMeters;
  }

  // 👇 3️⃣ СГЛАЖИВАНИЕ ПОЗИЦИИ (LOW-PASS FILTER)
  LatLng _smoothPosition(LatLng raw) {
    if (_smoothedPosition == null) {
      _smoothedPosition = raw;
      return raw;
    }

    const alpha = 0.15; // меньше — плавнее
    final lat =
        _smoothedPosition!.latitude +
        alpha * (raw.latitude - _smoothedPosition!.latitude);
    final lon =
        _smoothedPosition!.longitude +
        alpha * (raw.longitude - _smoothedPosition!.longitude);

    _smoothedPosition = LatLng(lat, lon);
    return _smoothedPosition!;
  }

  // 👇 4️⃣ СГЛАЖИВАНИЕ HEADING (ОЧЕНЬ ВАЖНО)
  double _smoothHeading(double raw) {
    const alpha = 0.2;

    double delta = raw - _smoothedHeading;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;

    _smoothedHeading += alpha * delta;
    return _smoothedHeading;
  }

  // 👇 5️⃣ LOOK-AHEAD (КАМЕРА СМОТРИТ ВПЕРЁД)
  LatLng _lookAhead(LatLng pos, double speed) {
    final distance = math.min(speed * 1.5, 20); // метров
    final rad = _smoothedHeading * math.pi / 180;

    final dLat = (distance / 111111) * math.cos(rad);
    final dLon =
        (distance / (111111 * math.cos(pos.latitude * math.pi / 180))) *
        math.sin(rad);

    return LatLng(pos.latitude + dLat, pos.longitude + dLon);
  }

  // 👇 6️⃣ DEAD-RECKONING (МЕЖДУ GPS)
  LatLng _predict(Position pos) {
    if (_lastValidGpsTime == null) {
      _lastValidGpsTime = DateTime.now();
      return LatLng(pos.latitude, pos.longitude);
    }

    final now = DateTime.now();
    final dt = now.difference(_lastValidGpsTime!).inMilliseconds / 1000;
    _lastValidGpsTime = now;

    final distance = pos.speed * dt;
    final rad = _smoothedHeading * math.pi / 180;

    final dLat = (distance / 111111) * math.cos(rad);
    final dLon =
        (distance / (111111 * math.cos(pos.latitude * math.pi / 180))) *
        math.sin(rad);

    return LatLng(pos.latitude + dLat, pos.longitude + dLon);
  }

  // 👇 7️⃣ ФИНАЛЬНЫЙ _onBackgroundLocation (теперь ОБНОВЛЯЕТ маршрут в UI!)
  void _onBackgroundLocation(dynamic data) {
    if (!mounted) return;
    if (data['lat'] == null || data['lon'] == null) return;

    final double newHeading = (data['heading'] as num?)?.toDouble() ?? _heading;

    final position = Position(
      latitude: data['lat'],
      longitude: data['lon'],
      timestamp: data['timestamp'] != null
          ? DateTime.parse(data['timestamp'])
          : DateTime.now(),
      accuracy: 5,
      altitude: 0,
      heading: newHeading, // Используем сглаженное ниже
      speed: (data['speed'] as num?)?.toDouble() ?? 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

    if (_currentPosition != null && _isGpsJump(_currentPosition!, position)) {
      print('IGNORING GPS JUMP'); // Лог для отладки
      return; // ❌ игнорируем скачок
    }

    _currentPosition = position;

    final rawHeading = position.heading;
    _smoothedHeading = _smoothHeading(rawHeading);

    final predicted = _predict(position);
    final smoothed = _smoothPosition(predicted);

    setState(() {
      if (_state == RunState.searchingGps) {
        _state = RunState.ready;
        _mapController.move(LatLng(position.latitude, position.longitude), 15);
      }

      if (_state == RunState.running) {
        // ✅ ДОБАВЛЕНО: _route.add(...) - теперь маршрут обновляется в реальном времени в UI
        _route.add(
          RoutePoint(
            lat: position.latitude,
            lon: position.longitude,
            timestamp: position.timestamp ?? DateTime.now(),
            speed: position.speed,
          ),
        );

        _calculateDistance();
        _checkProximity(position);
      }
    });

    _moveCamera(smoothed);
  }

  // 👇 8️⃣ ФИНАЛЬНЫЙ _moveCamera (БЕЗ ДЁРГАНИЙ)
  void _moveCamera(LatLng pos) {
    // 1️⃣ FOLLOW MODE
    if (!_followUser || _state != RunState.running) return;

    final now = DateTime.now();
    if (_lastCameraUpdate != null &&
        now.difference(_lastCameraUpdate!) < _cameraInterval)
      return;

    final target = _lookAhead(pos, _currentPosition?.speed ?? 0);

    _mapController.moveAndRotate(target, _calculateZoom(), _smoothedHeading);

    _lastCameraUpdate = now;
  }

  // 👇 3️⃣ АДАПТИВНЫЙ ZOOM ПО СКОРОСТИ (из предыдущего патча)
  double _calculateZoom() {
    final speed = _currentPosition?.speed ?? 0;

    if (speed < 1.5) return 17.5; // шаг
    if (speed < 3.5) return 17.0; // медленный бег
    if (speed < 5.5) return 16.5; // норм бег
    if (speed < 7.5) return 16.0; // быстрый
    return 15.5; // спринт
  }

  // 👇 9️⃣ МЕТОД ВОССТАНОВЛЕНИЯ МАРШРУТА ИЗ ФОНА
  Future<void> _restoreRouteFromBackground() async {
    final restoredRoute = await RunRepository().getActiveRoute();

    if (!mounted || restoredRoute.isEmpty) return;

    setState(() {
      _route = restoredRoute; // ✅ УСТАНАВЛИВАЕМ маршрут из Hive
      _currentPosition = Position(
        latitude: restoredRoute.last.lat,
        longitude: restoredRoute.last.lon,
        timestamp: restoredRoute.last.timestamp ?? DateTime.now(),
        accuracy: 5,
        altitude: 0,
        heading: _smoothedHeading,
        speed: restoredRoute.last.speed,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    });

    _mapController.move(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      _calculateZoom(),
    );
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

  void _calculateDistance() {
    if (_route.length < 2) return;

    double lastDistance = 0.0;
    if (_route.length >= 2) {
      final pos1 = _route[_route.length - 2];
      final pos2 = _route[_route.length - 1];
      lastDistance = Geolocator.distanceBetween(
        pos1.lat,
        pos1.lon,
        pos2.lat,
        pos2.lon,
      );
    }

    setState(() {
      _totalDistanceInMeters += lastDistance;
      _distance = _totalDistanceInMeters / 1000;
    });
    _distanceController.reset();
    _distanceController.forward();
  }

  void _checkProximity(Position position) {
    _factsService.checkProximityToPoi(position);
  }

  // ❗️ИСПРАВЛЕНО: _startGeneralFacts с кэшированием и await
  void _startGeneralFacts() {
    _factsTimer?.cancel();
    _factsTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      // ❗️async
      if (_state == RunState.running && _route.length > 5) {
        final now = DateTime.now();
        if (_lastFactTime == null ||
            now.difference(_lastFactTime!) >= const Duration(minutes: 3)) {
          _lastFactTime = now;

          // ❗️ИСПРАВЛЕНО: дожидаемся и кэшируем индексы
          final allSpokenIndices =
              _cachedAllSpokenIndices ??
              await RunRepository().getAllSpokenFactIndices();
          _cachedAllSpokenIndices =
              allSpokenIndices; // Кэшируем на время сессии

          final availableIndices = <int>[];
          for (int i = 0; i < kGeneralFacts.length; i++) {
            if (!allSpokenIndices.contains(i)) {
              // Теперь contains вызывается на List<int>
              availableIndices.add(i);
            }
          }

          int? randomIndex;
          if (availableIndices.isNotEmpty) {
            randomIndex =
                availableIndices[DateTime.now().millisecondsSinceEpoch %
                    availableIndices.length];
          } else {
            randomIndex =
                DateTime.now().millisecondsSinceEpoch % kGeneralFacts.length;
          }

          _tts.speak(
            "Интересный факт о Ростове-на-Дону: ${kGeneralFacts[randomIndex]}",
          );

          setState(() {
            _factsCount++;
          });

          if (randomIndex != null) {
            _lastFactIndices.add(randomIndex);
          }
        }
      }
    });
  }

  void _speakButtonAction(String text) {
    _tts.speak(text);
  }

  void _startCountdown() {
    setState(() {
      _state = RunState.countdown;
      _countdown = 3;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() {
          _countdown--;
        });
      } else {
        _countdownTimer?.cancel();
        _startRun();
      }
    });
  }

  void _startRun() async {
    if (mounted) {
      setState(() {
        _state = RunState.running;
        _followUser = true; // 1️⃣ FOLLOW MODE
        _runStartTime = DateTime.now();
        _route = []; // Сбрасываем UI маршрут
        _factsCount = 0;
        _distance = 0.0;
        _totalDistanceInMeters = 0.0;
        _lastFactTime = null;
        _lastFactIndices.clear();
        _lastCameraUpdate = null;
        _lastValidGpsTime = null; // Сброс при старте
        _smoothedPosition = null; // Сброс сглаженной позиции
        _smoothedHeading = 0.0; // Сброс сглаженного направления
        _elapsedRunTime = Duration.zero;

        if (_currentPosition != null) {
          _startPoint = LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          );
        }
      });
    }

    // ✅ ОЧИСТИТЬ АКТИВНЫЙ МАРШРУТ ПРИ СТАРТЕ
    await RunRepository().clearActiveRoute();

    _runTicker?.cancel();
    _runTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state == RunState.running) {
        setState(() {
          _elapsedRunTime += const Duration(seconds: 1);
        });
      }
    });

    _audio.playMusic(_musicMode);
    _startGeneralFacts(); // Теперь вызывает исправленную версию

    _speakButtonAction("Тренировка началась");
  }

  void _stopRun() {
    _followUser = false; // 1️⃣ FOLLOW MODE

    // FlutterBackgroundService().invoke('stopService'); // УДАЛЕНО - НЕ ОСТАНАВЛИВАЕМ СЕРВИС
    _runTicker?.cancel();

    if (mounted) {
      setState(() {
        _state = RunState.finished;
      });
    }

    _audio.stopMusic();
    _factsTimer?.cancel();
    _saveRunSession();

    _speakButtonAction("Тренировка окончена");

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _currentSession != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                SessionDetailScreen(session: _currentSession!),
          ),
        );
      }
    });
  }

  void _pauseRun() {
    _followUser = false; // 1️⃣ FOLLOW MODE
    _runTicker?.cancel();

    if (mounted) {
      setState(() {
        _state = RunState.paused;
      });
    }

    _speakButtonAction("Тренировка на паузе");
  }

  void _resumeRun() {
    _followUser = true; // 1️⃣ FOLLOW MODE
    _runTicker?.cancel();
    _runTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state == RunState.running) {
        setState(() {
          _elapsedRunTime += const Duration(seconds: 1);
        });
      }
    });

    if (mounted) {
      setState(() {
        _state = RunState.running;
      });
    }

    _speakButtonAction("Тренировка продолжается");
  }

  Future<void> _saveRunSession() async {
    final session = RunSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      distance: _distance,
      duration: _elapsedRunTime.inSeconds,
      factsCount: _factsCount,
      route: _route, // Теперь _route - это восстановленный маршрут
      spokenFactIndices: _lastFactIndices.toList(),
    );

    _currentSession = session;

    await RunRepository().saveSession(session);

    if (mounted) {
      setState(() {
        _history.add(session);
      });
    }

    print("💾 Сессия сохранена: $_distance км, $_factsCount фактов");
  }

  String get _currentPace {
    if (_distance <= 0) return '--';

    final secondsPerKm = _elapsedRunTime.inSeconds / _distance;
    final minutes = (secondsPerKm / 60).floor();
    final seconds = (secondsPerKm % 60).round();

    return '$minutes:${seconds.toString().padLeft(2, "0")}';
  }

  double _calculateCalories() {
    const double weightKg = 75;
    const double metRunning = 9.8;

    final hours = _elapsedRunTime.inSeconds / 3600;
    return metRunning * weightKg * hours;
  }

  List<Polyline> _buildSpeedPolylines() {
    final polylines = <Polyline>[];
    final smoothedRoute = _smoothRoute(_route, 5);

    for (int i = 1; i < smoothedRoute.length; i++) {
      final p1 = smoothedRoute[i - 1];
      final p2 = smoothedRoute[i];

      Color color;
      if (p1.speed < 2) {
        color = Colors.blue;
      } else if (p1.speed < 5) {
        color = const Color(0xFF9C27B0);
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

  List<RoutePoint> _smoothRoute(List<RoutePoint> route, int windowSize) {
    if (route.length < windowSize) return route;

    final smoothed = <RoutePoint>[];
    final halfWindow = windowSize ~/ 2;

    for (int i = 0; i < route.length; i++) {
      double latSum = 0;
      double lonSum = 0;
      int count = 0;

      for (int j = -halfWindow; j <= halfWindow; j++) {
        final idx = i + j;
        if (idx >= 0 && idx < route.length) {
          latSum += route[idx].lat;
          lonSum += route[idx].lon;
          count++;
        }
      }

      smoothed.add(
        RoutePoint(
          lat: latSum / count,
          lon: lonSum / count,
          timestamp: route[i].timestamp,
          speed: route[i].speed,
        ),
      );
    }

    return smoothed;
  }

  Duration _getCurrentRunTime() {
    return _elapsedRunTime;
  }

  @override
  Widget build(BuildContext context) {
    final currentRunTime = _getCurrentRunTime();
    final currentPace = _currentPace;
    final currentCalories = _calculateCalories().round();

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
              // ❌ 9️⃣ MapOptions (ПРОВЕРЬ) - rotation УДАЛЕН
              initialCenter: _currentPosition != null
                  ? LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    )
                  : const LatLng(47.2313, 39.7233),
              initialZoom: 16, // Изменён на 16
              // rotation: _smoothedHeading, // ❌ УДАЛЕН из MapOptions
              // interactionOptions: const InteractionOptions(
              //   flags: InteractiveFlag.all & ~InteractiveFlag.rotate, // ❌ УДАЛЕН из MapOptions
              // ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.running_historian',
              ),
              if ((_state == RunState.running || _state == RunState.finished) &&
                  _route.isNotEmpty)
                PolylineLayer(polylines: [..._buildSpeedPolylines()]),
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        // ✅ ИСПРАВЛЕНО: маркер = реальная позиция
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      width: 50,
                      height: 50,
                      child: const Icon(
                        // ✅ ИСПРАВЛЕНО: маркер НЕ вращается
                        Icons.navigation,
                        color: Colors.deepPurple,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              if (_state != RunState.init &&
                  _startPoint != null &&
                  _state != RunState.searchingGps)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _startPoint!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.flag,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              if (_state == RunState.finished && _route.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_route.last.lat, _route.last.lon),
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.fiber_manual_record,
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
          if (_state == RunState.running || _state == RunState.paused)
            Positioned(
              top: 50,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.route, color: Colors.white, size: 30),
                        const SizedBox(width: 8),
                        Text(
                          _distance.toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'км',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            Icon(Icons.access_time, color: Colors.white),
                            const SizedBox(height: 4),
                            Text(
                              '${currentRunTime.inMinutes.remainder(60).toString().padLeft(2, '0')}:${(currentRunTime.inSeconds.remainder(60)).toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              'Время',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Icon(Icons.speed, color: Colors.white),
                            const SizedBox(height: 4),
                            Text(
                              currentPace,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              'Темп',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Icon(
                              Icons.local_fire_department,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentCalories.toString(),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              'Кал',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_state == RunState.searchingGps)
            Positioned(
              top: 50,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gps_fixed, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      '📡 Ищем твоё местоположение…',
                      style: TextStyle(color: Colors.white),
                    ),
                    const Spacer(),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_state == RunState.ready)
            Positioned(
              top: 50,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    const Text(
                      '📍 Местоположение найдено',
                      style: TextStyle(color: Colors.white),
                    ),
                    const Spacer(),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_state == RunState.countdown)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.8),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _countdown > 0 ? '$_countdown' : 'СТАРТ',
                        style: const TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.bold,
                          color: Colors.yellow,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _countdown > 0 ? 'Подготовьтесь!' : 'Бегите!',
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_state == RunState.ready)
                  ElevatedButton(
                    onPressed: _startCountdown,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(150, 60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Start', style: TextStyle(fontSize: 20)),
                  ),
                if (_state == RunState.running)
                  ElevatedButton(
                    onPressed: _pauseRun,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(150, 60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Pause', style: TextStyle(fontSize: 20)),
                  ),
                if (_state == RunState.paused)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: _resumeRun,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(120, 60),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Resume',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _stopRun,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(120, 60),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Stop',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                if (_state == RunState.finished)
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _state = RunState.searchingGps;
                        _followUser =
                            true; // Сбрасываем follow при новой тренировке
                        _route.clear(); // Очищаем UI маршрут
                        _startPoint = null;
                        _distance = 0.0;
                        _totalDistanceInMeters = 0.0;
                        _elapsedRunTime = Duration.zero;
                        _factsCount = 0;
                        _lastFactTime = null;
                        _lastFactIndices.clear();
                        _lastCameraUpdate = null;
                        _lastValidGpsTime = null; // Сброс при новой тренировке
                        _smoothedPosition = null; // Сброс сглаженной позиции
                        _smoothedHeading = 0.0; // Сброс сглаженного направления
                        _cachedAllSpokenIndices = null; // Сброс кэша индексов
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(200, 60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Новая тренировка',
                      style: TextStyle(fontSize: 20),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
