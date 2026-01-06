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

// 👇 НОВОЕ: стейт-машина
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

class _RunScreenState extends State<RunScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription? _backgroundLocationSubscription;
  Timer? _factsTimer;
  bool _isRunning = false;
  bool _showResults = false;
  final AudioService _audio = AudioService();
  late final TtsService _tts;
  late final FactsService _factsService;
  List<RoutePoint> _route = [];
  DateTime? _runStartTime;
  DateTime? _runEndTime;
  int _factsCount = 0;
  double _distance = 0.0;
  double _totalDistanceInMeters = 0.0;
  List<RunSession> _history = [];
  MusicMode _musicMode = MusicMode.external;
  DateTime? _lastFactTime;
  bool _isPaused = false;
  double _heading = 0.0;

  final Set<int> _lastFactIndices = <int>{};
  DateTime? _lastCameraMove;
  final List<RoutePoint> _smoothBuffer = [];

  // 👇 НОВОЕ: стейт-машина
  RunState _state = RunState.init;

  // 👇 НОВОЕ: таймер обратного отсчёта
  Timer? _countdownTimer;
  int _countdown = 3;

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
    _startSearchingGps(); // 👈 НОВОЕ: запускаем стейт-машину
  }

  // 👇 НОВОЕ: метод поиска GPS
  Future<void> _startSearchingGps() async {
    setState(() {
      _state = RunState.searchingGps;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }

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

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      if (!mounted) return;

      setState(() {
        _currentPosition = position;
        _state = RunState.ready; // 👈 ПЕРЕХОД: SEARCHING_GPS → READY
      });

      _mapController.move(LatLng(position.latitude, position.longitude), 15);
    } catch (e) {
      print('Ошибка при поиске GPS: $e');
      setState(() {
        _state = RunState.init; // 👈 ВОЗВРАТ К НАЧАЛУ
      });
    }
  }

  // 👇 НОВОЕ: метод обратного отсчёта
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
        _startRun(); // 👈 Запускаем тренировку
      }
    });
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

  void _moveCamera(Position position) {
    final now = DateTime.now();
    if (_lastCameraMove == null ||
        now.difference(_lastCameraMove!) > const Duration(seconds: 3)) {
      final offset = 0.0003;
      final target = LatLng(
        position.latitude + offset * math.cos(_heading * math.pi / 180),
        position.longitude + offset * math.sin(_heading * math.pi / 180),
      );

      _mapController.move(target, 17);
      _lastCameraMove = now;
    }
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

  void _onBackgroundLocation(dynamic data) {
    if (!mounted) return;

    final position = Position(
      latitude: data['lat'],
      longitude: data['lon'],
      timestamp: data['timestamp'] != null
          ? DateTime.parse(data['timestamp'])
          : DateTime.now(),
      accuracy: 5,
      altitude: 0,
      heading: _heading,
      speed: data['speed'] ?? 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

    setState(() {
      _currentPosition = position;

      if (_state == RunState.running && !_isPaused) {
        _route.add(RoutePoint.fromPosition(position));
        _calculateDistance();
        _checkProximity(position);
      }
    });

    _moveCamera(position);
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

  void _startGeneralFacts() {
    _factsTimer?.cancel();
    _factsTimer = Timer.periodic(Duration(minutes: kFactsIntervalMinutes), (timer) {
      if (_state == RunState.running && !_isPaused && _route.length > 5) {
        final now = DateTime.now();
        if (_lastFactTime == null ||
            now.difference(_lastFactTime!) >= Duration(minutes: kMinIntervalBetweenFacts)) {
          _lastFactTime = now;

          final allSpokenIndices = RunRepository().getAllSpokenFactIndices();

          final availableIndices = <int>[];
          for (int i = 0; i < kGeneralFacts.length; i++) {
            if (!allSpokenIndices.contains(i)) {
              availableIndices.add(i);
            }
          }

          int? randomIndex;
          if (availableIndices.isNotEmpty) {
            randomIndex = availableIndices[DateTime.now().millisecondsSinceEpoch % availableIndices.length];
          } else {
            randomIndex = DateTime.now().millisecondsSinceEpoch % kGeneralFacts.length;
          }

          _tts.speak("Интересный факт о Ростове-на-Дону: ${kGeneralFacts[randomIndex]}");

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

  void _startRun() async {
    await initBackgroundService();
    FlutterBackgroundService().startService();

    if (mounted) {
      setState(() {
        _state = RunState.running;
        _runStartTime = DateTime.now();
        _route = [];
        _factsCount = 0;
        _distance = 0.0;
        _totalDistanceInMeters = 0.0;
        _lastFactTime = null;
        _isPaused = false;
        _lastFactIndices.clear();
        _lastCameraMove = null;
        _smoothBuffer.clear();
      });
    }

    _audio.playMusic(_musicMode);
    _startGeneralFacts();
    
    _speakButtonAction("Тренировка началась");
  }

  void _stopRun() {
    FlutterBackgroundService().invoke('stopService');

    if (mounted) {
      setState(() {
        _state = RunState.finished;
        _runEndTime = DateTime.now();
      });
    }
    _audio.stopMusic();
    _factsTimer?.cancel();
    _saveRunSession();
    
    _speakButtonAction("Тренировка окончена");
  }

  void _pauseRun() {
    if (mounted) {
      setState(() {
        _state = RunState.paused;
        _isPaused = true;
      });
    }
    
    _speakButtonAction("Тренировка на паузе");
  }

  void _resumeRun() {
    if (mounted) {
      setState(() {
        _state = RunState.running;
        _isPaused = false;
      });
    }
    
    _speakButtonAction("Тренировка продолжается");
  }

  Future<void> _saveRunSession() async {
    final session = RunSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      distance: _distance,
      duration: _runEndTime!.difference(_runStartTime!).inSeconds,
      factsCount: _factsCount,
      route: _route,
      spokenFactIndices: _lastFactIndices.toList(),
    );

    await RunRepository().saveSession(session);

    if (mounted) {
      setState(() {
        _history.add(session);
      });
    }

    print("💾 Сессия сохранена: $_distance км, $_factsCount фактов");
  }

  List<Polyline> _buildSpeedPolylines() {
    final polylines = <Polyline>[];

    for (int i = 1; i < _route.length; i++) {
      final p1 = _route[i - 1];
      final p2 = _route[i];

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
          points: [
            LatLng(p1.lat, p1.lon),
            LatLng(p2.lat, p2.lon),
          ],
          strokeWidth: 5,
          color: color,
        ),
      );
    }

    return polylines;
  }

  @override
  void dispose() {
    _backgroundLocationSubscription?.cancel();
    _factsTimer?.cancel();
    _countdownTimer?.cancel(); // 👈 Отмена таймера отсчёта
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

  @override
  Widget build(BuildContext context) {
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
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.running_historian',
              ),
              if (_state == RunState.running && _route.isNotEmpty)
                PolylineLayer(
                  polylines: [
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
                        angle: _heading * math.pi / 180,
                        child: Icon(
                          Icons.navigation,
                          color: Colors.deepPurple,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
              if (_state == RunState.finished && _route.isNotEmpty)
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
          // 👇 НОВОЕ: оверлей по стейту
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
                        style: TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.bold,
                          color: Colors.yellow,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _countdown > 0 ? 'Подготовьтесь!' : 'Бегите!',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // 👇 Кнопки по стейту
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_state == RunState.ready)
                  ElevatedButton(
                    onPressed: _startCountdown, // 👈 НАЧИНАЕМ ОТСЧЁТ
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Start'),
                  ),
                if (_state == RunState.running)
                  ElevatedButton(
                    onPressed: _pauseRun,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Pause'),
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
                        ),
                        child: const Text('Resume'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _stopRun,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Stop'),
                      ),
                    ],
                  ),
                if (_state == RunState.finished)
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _state = RunState.searchingGps;
                        _startSearchingGps();
                      });
                    },
                    child: const Text('Новая тренировка'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}