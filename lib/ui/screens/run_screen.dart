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
import 'package:running_historian/config/constants.dart';
import 'package:running_historian/services/tts_service.dart';
import 'package:running_historian/services/audio_service.dart';
import 'package:running_historian/domain/landmark.dart';
import 'package:running_historian/ui/screens/history_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:running_historian/services/facts_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:running_historian/services/background_service.dart';
import 'dart:math' as math;

// 👇 СТЕЙТ-МАШИНА
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
  StreamSubscription? _backgroundLocationSubscription;
  Timer? _factsTimer;
  
  // 👇 НОВЫЙ ТАЙМЕР ДЛЯ СИНХРОНИЗАЦИИ
  Timer? _runTicker;
  Duration _elapsedRunTime = Duration.zero;
  
  final AudioService _audio = AudioService();
  late final TtsService _tts;
  late final FactsService _factsService;
  List<RoutePoint> _route = [];
  DateTime? _runStartTime;
  DateTime? _pauseStartTime;
  Duration _totalRunTime = Duration.zero;
  int _factsCount = 0;
  double _distance = 0.0;
  double _totalDistanceInMeters = 0.0;
  List<RunSession> _history = [];
  MusicMode _musicMode = MusicMode.external;
  DateTime? _lastFactTime;
  double _heading = 0.0;
  LatLng? _startPoint;

  final Set<int> _lastFactIndices = <int>{};
  DateTime? _lastCameraMove;
  final List<RoutePoint> _smoothBuffer = [];

  RunState _state = RunState.init;

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
    _initBackgroundListener();
    _startSearchingGps();
  }

  void _initBackgroundListener() {
    _backgroundLocationSubscription = FlutterBackgroundService()
        .on('locationUpdate')
        .listen(_onBackgroundLocation);
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

  Future<void> _loadHistory() async {
    _history = await RunRepository().getHistory();
    if (mounted) {
      setState(() {});
    }
  }

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
        _state = RunState.ready;
        _startPoint = null;
      });

      _mapController.move(LatLng(position.latitude, position.longitude), 15);
    } catch (e) {
      print('Ошибка при поиске GPS: $e');
      setState(() {
        _state = RunState.init;
      });
    }
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

      if (_state == RunState.running) {
        _route.add(RoutePoint.fromPosition(position));
        _calculateDistance();
        _checkProximity(position);
      }
    });

    _moveCamera(position);
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
      if (_state == RunState.running && _route.length > 5) {
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
    await initBackgroundService();
    FlutterBackgroundService().startService();

    if (mounted) {
      setState(() {
        _state = RunState.running;
        _runStartTime = DateTime.now();
        _pauseStartTime = null;
        _totalRunTime = Duration.zero;
        _elapsedRunTime = Duration.zero; // 👈 СБРАСЫВАЕМ ВРЕМЯ
        _route = [];
        _factsCount = 0;
        _distance = 0.0;
        _totalDistanceInMeters = 0.0;
        _lastFactTime = null;
        _lastFactIndices.clear();
        _lastCameraMove = null;
        _smoothBuffer.clear();
        
        if (_currentPosition != null) {
          _startPoint = LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          );
        }
      });
    }

    // 👇 ЗАПУСКАЕМ СИНХРОНИЗИРОВАННЫЙ ТАЙМЕР
    _runTicker?.cancel();
    _runTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state == RunState.running) {
        setState(() {
          _elapsedRunTime += const Duration(seconds: 1);
        });
      }
    });

    _audio.playMusic(_musicMode);
    _startGeneralFacts();
    
    _speakButtonAction("Тренировка началась");
  }

  void _stopRun() {
    FlutterBackgroundService().invoke('stopService');

    // 👇 ОСТАНАВЛИВАЕМ ТАЙМЕР
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
  }

  void _pauseRun() {
    // 👇 ОСТАНАВЛИВАЕМ ТАЙМЕР
    _runTicker?.cancel();

    if (mounted) {
      setState(() {
        _state = RunState.paused;
        _pauseStartTime = DateTime.now();
      });
    }
    
    _speakButtonAction("Тренировка на паузе");
  }

  void _resumeRun() {
    // 👇 ВОЗОБНОВЛЯЕМ ТАЙМЕР
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
        if (_pauseStartTime != null) {
          _totalRunTime += DateTime.now().difference(_pauseStartTime!);
          _pauseStartTime = null;
        }
      });
    }
    
    _speakButtonAction("Тренировка продолжается");
  }

  Future<void> _saveRunSession() async {
    final session = RunSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      distance: _distance,
      duration: _elapsedRunTime.inSeconds, // 👈 ИСПОЛЬЗУЕМ СИНХРОНИЗИРОВАННОЕ ВРЕМЯ
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

    print("💾 Сессия сохранена: $_distance км, ${_elapsedRunTime.inSeconds} сек, $_factsCount фактов");
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

  // 👇 ПРАВИЛЬНЫЙ РАСЧЁТ ТЕМПА
  String get _currentPace {
    if (_distance <= 0) return '--';
    
    final secondsPerKm = _elapsedRunTime.inSeconds / _distance;
    final minutes = (secondsPerKm / 60).floor();
    final seconds = (secondsPerKm % 60).round();
    
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // 👇 РЕАЛИСТИЧНЫЙ РАСЧЁТ КАЛОРИЙ
  double _calculateCalories() {
    const double weightKg = 75; // можно сделать настройкой позже
    const double metRunning = 9.8; // бег 8–9 км/ч
    
    final hours = _elapsedRunTime.inSeconds / 3600;
    return metRunning * weightKg * hours;
  }

  @override
  void dispose() {
    _backgroundLocationSubscription?.cancel();
    _factsTimer?.cancel();
    _countdownTimer?.cancel();
    _runTicker?.cancel(); // 👈 ОТМЕНА НОВОГО ТАЙМЕРА
    _distanceController.dispose();
    _factController.dispose();
    _tts.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentDistance = _distance;
    final currentPace = _currentPace; // 👈 ИСПОЛЬЗУЕМ СИНХРОНИЗИРОВАННЫЙ ТЕМП
    final currentCalories = _calculateCalories().round(); // 👈 ПРАВИЛЬНЫЙ РАСЧЁТ КАЛОРИЙ
    final currentRunTime = _elapsedRunTime; // 👈 ИСПОЛЬЗУЕМ СИНХРОНИЗИРОВАННОЕ ВРЕМЯ

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
              if ((_state == RunState.running || _state == RunState.finished) && _route.isNotEmpty)
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
                        child: const Icon(
                          Icons.navigation,
                          color: Colors.deepPurple,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
              if (_state != RunState.init && _startPoint != null && _state != RunState.searchingGps)
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
                          currentDistance.toStringAsFixed(2),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'км',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            const Icon(Icons.access_time, color: Colors.white),
                            const SizedBox(height: 4),
                            Text(
                              '${currentRunTime.inMinutes.remainder(60).toString().padLeft(2, '0')}:${(currentRunTime.inSeconds.remainder(60)).toString().padLeft(2, '0')}',
                              style: const TextStyle(
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
                            const Icon(Icons.speed, color: Colors.white),
                            const SizedBox(height: 4),
                            Text(
                              currentPace,
                              style: const TextStyle(
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
                            const Icon(Icons.local_fire_department, color: Colors.white),
                            const SizedBox(height: 4),
                            Text(
                              currentCalories.toString(),
                              style: const TextStyle(
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
                        child: const Text('Resume', style: TextStyle(fontSize: 18)),
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
                        child: const Text('Stop', style: TextStyle(fontSize: 18)),
                      ),
                    ],
                  ),
                if (_state == RunState.finished)
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _state = RunState.searchingGps;
                        _startPoint = null;
                        _startSearchingGps();
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
                    child: const Text('Новая тренировка', style: TextStyle(fontSize: 20)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}