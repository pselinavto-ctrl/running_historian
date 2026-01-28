// lib/ui/screens/run_screen.dart
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
import 'package:running_historian/services/poi_service.dart';
import 'package:running_historian/services/fact_bank_service.dart';
import 'package:running_historian/services/city_resolver.dart';

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
  late final PoiService _poiService;
  late final FactBankService _factBankService;
  List<RoutePoint> _route = [];
  DateTime? _runStartTime;
  RunSession? _currentSession;
  int _factsCount = 0;
  double _distance = 0.0;
  double _totalDistanceInMeters = 0.0;
  List<RunSession> _history = [];
  MusicMode _musicMode = MusicMode.external;
  DateTime? _lastFactTime;
  double _heading = 0.0;
  LatLng? _startPoint;
  final Set<int> _lastFactIndices = <int>{};
  RunState _state = RunState.searchingGps;
  Timer? _countdownTimer;
  int _countdown = 3;
  late AnimationController _distanceController;
  late Animation<double> _distanceAnimation;
  late AnimationController _factController;
  late Animation<double> _factAnimation;
  bool _followUser = true;
  LatLng? _smoothedPosition;
  double _smoothedHeading = 0.0;
  DateTime? _lastCameraUpdate;
  DateTime? _lastValidGpsTime;
  static const double _maxJumpMeters = 40;
  static const Duration _cameraInterval = Duration(milliseconds: 120);
  List<int>? _cachedAllSpokenIndices;
  LatLng? _lastSmoothedPosition;
  final Set<String> _shownPoiIds = <String>{};
  final Set<int> _spokenFactIndices = <int>{};
  String? _currentCity;
  
  // 🔑 ОПТИМИЗИРОВАННЫЙ КАЛМАН ДЛЯ ГОРОДСКОЙ СРЕДЫ (точность 5-7 м)
  final KalmanLatLng _kalman = KalmanLatLng(6.0, 2.5);
  DateTime? _lastKalmanTime;
  double _smoothedSpeed = 0.0;

  @override
  void initState() {
    super.initState();
    _tts = TtsService(_audio)..init();
    _factsService = FactsService(_tts);
    _poiService = PoiService()..init();
    _factBankService = FactBankService();
    _initAnimations();
    _loadHistory();
    _requestLocationPermissionAndStart();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _requestLocationPermissionAndStart() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      await Future.delayed(const Duration(seconds: 1));
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _state = RunState.searchingGps;
          });
        }
        return;
      }
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _state = RunState.searchingGps;
        });
      }
      return;
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      if (mounted) {
        setState(() {
          _state = RunState.searchingGps;
        });
      }
      return;
    }
    var notificationPermission = await Permission.notification.status;
    if (notificationPermission.isDenied) {
      notificationPermission = await Permission.notification.request();
    }
    _startBackgroundService();
    _initBackgroundListener();
    _attemptToGetCurrentPosition();
  }

  void _startBackgroundService() async {
    await initBackgroundService();
    bool started = await FlutterBackgroundService().startService();
    print('SERVICE STARTED = $started');
    if (started) {
      final isRunning = await FlutterBackgroundService().isRunning();
      print('SERVICE RUNNING = $isRunning');
    }
  }

  void _initBackgroundListener() {
    _backgroundLocationSubscription =
        FlutterBackgroundService().on('locationUpdate').listen(_onBackgroundLocation);
    print('Подписка на фоновое обновление местоположения установлена');
  }

  Future<void> _attemptToGetCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _smoothedPosition = LatLng(position.latitude, position.longitude);
          _lastSmoothedPosition = _smoothedPosition;
          if (_state == RunState.searchingGps) {
            _state = RunState.ready;
          }
          // 🔑 УСТАНАВЛИВАЕМ ТОЧКУ СТАРТА СРАЗУ ПРИ ПОЛУЧЕНИИ ПОЗИЦИИ
          _startPoint = _smoothedPosition;
        });
        _mapController.move(_smoothedPosition!, 15);
        print('✅ Получена позиция: ${position.latitude}, ${position.longitude}');
      }
    } catch (e) {
      print('❌ Не удалось получить позицию: $e');
      if (_state == RunState.searchingGps && mounted) {
        await Future.delayed(const Duration(seconds: 2));
        _attemptToGetCurrentPosition();
      }
    }
  }

  void _initAnimations() {
    _distanceController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _distanceAnimation = Tween<double>(begin: 0, end: 1).animate(_distanceController);
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
    WidgetsBinding.instance.removeObserver(this);
    FlutterBackgroundService().invoke('stopService');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restoreRouteFromBackground();
      if (_state == RunState.searchingGps) {
        unawaited(_attemptToGetCurrentPosition());
      }
    }
  }

  Future<void> _loadHistory() async {
    _history = await RunRepository().getHistory();
    if (mounted) {
      setState(() {});
    }
  }

  bool _isGpsJump(Position prev, Position next) {
    final d = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      next.latitude,
      next.longitude,
    );
    return d > _maxJumpMeters;
  }

  LatLng _smoothPosition(LatLng raw) {
    if (_smoothedPosition == null) {
      _smoothedPosition = raw;
      return raw;
    }
    const alpha = 0.15;
    final lat = _smoothedPosition!.latitude + alpha * (raw.latitude - _smoothedPosition!.latitude);
    final lon = _smoothedPosition!.longitude + alpha * (raw.longitude - _smoothedPosition!.longitude);
    _smoothedPosition = LatLng(lat, lon);
    return _smoothedPosition!;
  }

  double _smoothHeading(double raw) {
    const alpha = 0.2;
    double delta = raw - _smoothedHeading;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    _smoothedHeading += alpha * delta;
    return _smoothedHeading;
  }

  LatLng _lookAhead(LatLng pos, double speed) {
    final distance = math.min(speed * 0.7, 8);
    final rad = _smoothedHeading * math.pi / 180;
    final dLat = (distance / 111111) * math.cos(rad);
    final dLon = (distance / (111111 * math.cos(pos.latitude * math.pi / 180))) * math.sin(rad);
    return LatLng(pos.latitude + dLat, pos.longitude + dLon);
  }

  void _onBackgroundLocation(dynamic data) {
    if (!mounted || data['lat'] == null || data['lon'] == null) return;
    
    final position = Position(
      latitude: data['lat'],
      longitude: data['lon'],
      timestamp: data['timestamp'] != null ? DateTime.parse(data['timestamp']) : DateTime.now(),
      accuracy: (data['accuracy'] as num?)?.toDouble() ?? 5.0,
      altitude: 0,
      heading: (data['heading'] as num?)?.toDouble() ?? _heading,
      speed: (data['speed'] as num?)?.toDouble() ?? 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

    if (_currentPosition != null && _isGpsJump(_currentPosition!, position)) {
      print('IGNORING GPS JUMP');
      return;
    }

    _currentPosition = position;
    
    final rawHeading = position.heading;
    _smoothedHeading = _smoothHeading(rawHeading);
    final rawPos = LatLng(position.latitude, position.longitude);
    final smoothed = _smoothPosition(rawPos);
    _lastSmoothedPosition = smoothed;
    
    setState(() {
      if (_state == RunState.searchingGps) {
        _state = RunState.ready;
        _mapController.move(smoothed, 15);
      }
      
      if (_state == RunState.running) {
        _route.add(RoutePoint(
          lat: smoothed.latitude,
          lon: smoothed.longitude,
          timestamp: position.timestamp,
          speed: position.speed,
        ));
        _calculateDistance();
        _checkProximity(position);
      }
    });
    
    _moveCamera(smoothed);
  }

  double _smoothSpeed(double raw) {
    const alpha = 0.3;
    _smoothedSpeed = _smoothedSpeed + alpha * (raw - _smoothedSpeed);
    return _smoothedSpeed;
  }

  void _moveCamera(LatLng pos) {
    if (!_followUser || _state != RunState.running) return;
    final now = DateTime.now();
    if (_lastCameraUpdate != null && now.difference(_lastCameraUpdate!) < _cameraInterval) return;
    final target = _lookAhead(pos, _currentPosition?.speed ?? 0);
    _mapController.move(target, _calculateZoom());
    _lastCameraUpdate = now;
  }

  double _calculateZoom() {
    final speed = _currentPosition?.speed ?? 0;
    if (speed < 1.5) return 17.5;
    if (speed < 3.5) return 17.0;
    if (speed < 5.5) return 16.5;
    if (speed < 7.5) return 16.0;
    return 15.5;
  }

  Future<void> _restoreRouteFromBackground() async {
    final restoredRoute = await RunRepository().getActiveRoute();
    if (!mounted || restoredRoute.isEmpty) return;
    setState(() {
      _route = restoredRoute;
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
      _lastSmoothedPosition = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    });
    _mapController.move(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      _calculateZoom(),
    );
  }

  void _calculateDistance() {
    if (_route.length < 2) return;
    double lastDistance = 0.0;
    final pos1 = _route[_route.length - 2];
    final pos2 = _route[_route.length - 1];
    lastDistance = Geolocator.distanceBetween(pos1.lat, pos1.lon, pos2.lat, pos2.lon);
    setState(() {
      _totalDistanceInMeters += lastDistance;
      _distance = _totalDistanceInMeters / 1000;
    });
    _distanceController.reset();
    _distanceController.forward();
  }

  void _checkProximity(Position position) async {
    final poi = _poiService.getUnannouncedPoi(position.latitude, position.longitude);
    if (poi != null) {
      final factText = _poiService.formatPoiFact(poi);
      await _tts.speak(factText);
      poi.announced = true;
      await poi.save();
      _lastFactTime = DateTime.now();
      if (mounted) {
        setState(() {
          _factsCount++;
          _shownPoiIds.add(poi.id);
          _spokenFactIndices.add(poi.id.hashCode);
        });
      }
      return;
    }
    _factsService.checkProximityToPoi(position);
  }

  Widget _buildAudioGuideWidget() {
    String status;
    Color statusColor;
    IconData statusIcon;
    if (_tts.isSpeaking) {
      status = "Рассказываю...";
      statusColor = Colors.yellow;
      statusIcon = Icons.headphones;
    } else if (_tts.isPaused) {
      status = "Гид на паузе";
      statusColor = Colors.grey;
      statusIcon = Icons.headset_off;
    } else {
      status = "Слушаю город";
      statusColor = Colors.green;
      statusIcon = Icons.record_voice_over;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.3),
            blurRadius: 15,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'АУДИО-ГИД',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              if (_tts.isPaused) {
                _tts.resume();
              } else {
                _tts.pause();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _tts.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              _tts.stop();
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.skip_next_rounded,
                color: Colors.white70,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    double fontSize = 18,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
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
        timer.cancel();
        _startRun();
      }
    });
  }

  void _startRun() async {
    if (mounted) {
      setState(() {
        _state = RunState.running;
        _followUser = true;
        _runStartTime = DateTime.now();
        _route = [];
        _factsCount = 0;
        _distance = 0.0;
        _totalDistanceInMeters = 0.0;
        _lastFactTime = null;
        _lastFactIndices.clear();
        _lastCameraUpdate = null;
        _lastValidGpsTime = null;
        _smoothedHeading = 0.0;
        _elapsedRunTime = Duration.zero;
        _factsService.clearSessionState();
        _poiService.resetAnnouncedFlags();
        
        // 🔑 КРИТИЧЕСКИ ВАЖНО: НЕ СБРАСЫВАЕМ ПОЗИЦИИ!
        // Оставляем текущие значения для мгновенного отображения стрелки и точки старта
        // _smoothedPosition НЕ СБРАСЫВАЕМ
        
        // 🔑 УСТАНАВЛИВАЕМ ТОЧКУ СТАРТА СРАЗУ НА ОСНОВЕ ТЕКУЩЕЙ ПОЗИЦИИ
        if (_lastSmoothedPosition != null) {
          _startPoint = _lastSmoothedPosition;
        } else if (_currentPosition != null) {
          _startPoint = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
          _lastSmoothedPosition = _startPoint;
          _smoothedPosition = _startPoint;
        }
      });

      FlutterBackgroundService().invoke('startRun');
      
      // 🔑 ЗАГРУЗКА POI И ФАКТОВ В ФОНЕ (без блокировки UI)
      if (_currentPosition != null) {
        final lat = _currentPosition!.latitude;
        final lon = _currentPosition!.longitude;
        final delta = 0.018;
        unawaited(_poiService.loadPoiForBbox(lat - delta, lat + delta, lon - delta, lon + delta));
        
        unawaited(() async {
          final city = await CityResolver.detectCity(lat, lon);
          if (city != null && mounted) {
            setState(() { _currentCity = city; });
            await _factBankService.init();
            unawaited(_factBankService.replenishBank(city: city));
          }
        }());
      }
      
      await RunRepository().clearActiveRoute();
      
      _runTicker?.cancel();
      _runTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _state == RunState.running) {
          setState(() { _elapsedRunTime += const Duration(seconds: 1); });
        }
      });
      
      _audio.playMusic(_musicMode);
      _startGeneralFacts();
      _speakButtonAction("Тренировка началась");
    }
  }

  void _stopRun() {
    _followUser = false;
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
          MaterialPageRoute(builder: (context) => SessionDetailScreen(session: _currentSession!)),
        );
      }
    });
  }

  void _pauseRun() {
    _followUser = false;
    _runTicker?.cancel();
    if (mounted) {
      setState(() {
        _state = RunState.paused;
      });
    }
    _speakButtonAction("Тренировка на паузе");
  }

  void _resumeRun() {
    _followUser = true;
    _runTicker?.cancel();
    _runTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state == RunState.running) {
        setState(() { _elapsedRunTime += const Duration(seconds: 1); });
      }
    });
    if (mounted) {
      setState(() {
        _state = RunState.running;
      });
    }
    _speakButtonAction("Тренировка продолжается");
    if (_currentCity != null) {
      unawaited(_factBankService.replenishBank(city: _currentCity!));
    }
  }

  Future<void> _saveRunSession() async {
    final session = RunSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      distance: _distance,
      duration: _elapsedRunTime.inSeconds,
      factsCount: _factsCount,
      route: _route,
      spokenFactIndices: _spokenFactIndices.toList(),
      shownPoiIds: _shownPoiIds.toList(),
    );
    _currentSession = session;
    await RunRepository().saveSession(session);
    if (mounted) {
      setState(() {
        _history.add(session);
      });
    }
    print("💾 Сессия сохранена: $_distance км, $_factsCount фактов, ${_spokenFactIndices.length} индексов, ${_shownPoiIds.length} POI");
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

  // 🔑 СГЛАЖИВАНИЕ ТРЕКА ДЛЯ БОЛЕЕ ПЛАВНЫХ ЛИНИЙ (БЕЗ ОШИБКИ СО SPEED)
  List<LatLng> _smoothTrajectory(List<LatLng> points) {
    if (points.length < 2) return points;
    
    List<LatLng> smoothed = [];
    for (int i = 0; i < points.length; i++) {
      if (i == 0 || i == points.length - 1) {
        smoothed.add(points[i]);
        continue;
      }
      
      // Квадратичная интерполяция для плавных поворотов
      double lat = points[i-1].latitude * 0.25 + 
                  points[i].latitude * 0.5 + 
                  points[i+1].latitude * 0.25;
      double lon = points[i-1].longitude * 0.25 + 
                  points[i].longitude * 0.5 + 
                  points[i+1].longitude * 0.25;
      smoothed.add(LatLng(lat, lon));
    }
    return smoothed;
  }

  List<Polyline> _buildSpeedPolylines() {
    final polylines = <Polyline>[];
    
    // Получаем точки маршрута
    final points = _route.map((point) => LatLng(point.lat, point.lon)).toList();
    
    // 🔑 СГЛАЖИВАЕМ ТРЕК ДЛЯ БОЛЕЕ ПЛАВНЫХ ЛИНИЙ
    final smoothedPoints = _smoothTrajectory(points);
    
    for (int i = 1; i < smoothedPoints.length; i++) {
      // 🔑 ИСПОЛЬЗУЕМ ОРИГИНАЛЬНЫЕ ТОЧКИ МАРШРУТА ДЛЯ ОПРЕДЕЛЕНИЯ ЦВЕТА ПО СКОРОСТИ
      final p1 = _route[i - 1];
      Color color;
      if (p1.speed < 2) {
        color = Colors.blue;
      } else if (p1.speed < 5) {
        color = const Color(0xFF9C27B0);
      } else {
        color = Colors.red;
      }
      polylines.add(Polyline(
        points: [smoothedPoints[i-1], smoothedPoints[i]],
        strokeWidth: 5,
        color: color,
      ));
    }
    return polylines;
  }

  Duration _getCurrentRunTime() {
    return _elapsedRunTime;
  }

  void maybeReplenishFacts({String? city}) {
    if (city != null) {
      final size = _factBankService.getCityBankSize(city);
      if (size < 15) {
        unawaited(_factBankService.replenishBank(city: city));
      }
    }
  }

  void _startGeneralFacts() {
    _factsTimer?.cancel();
    _factsTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (_lastFactTime != null &&
          DateTime.now().difference(_lastFactTime!) < const Duration(minutes: 1, seconds: 50)) {
        return;
      }
      if (_state != RunState.running) return;
      if (_tts.isSpeaking) return;
      
      String? city;
      if (_currentPosition != null) {
        city = await CityResolver.detectCity(_currentPosition!.latitude, _currentPosition!.longitude);
        if (city != null && city != _currentCity) {
          setState(() { _currentCity = city; });
          unawaited(_factBankService.replenishBank(city: city));
        }
      }
      city ??= _currentCity;
      
      String? factText;
      if (city != null) {
        final cityFact = _factBankService.getCityFact(city);
        if (cityFact != null) {
          factText = cityFact.text;
          await _factBankService.markAsConsumed(cityFact);
        }
      }
      if (factText == null) {
        final generalFact = _factBankService.getGeneralFact();
        if (generalFact != null) {
          factText = generalFact.text;
          await _factBankService.markAsConsumed(generalFact);
        }
      }
      
      if (factText != null) {
        _lastFactTime = DateTime.now();
        await _tts.speak(factText);
        if (mounted) {
          setState(() {
            _factsCount++;
            _spokenFactIndices.add(factText.hashCode);
          });
        }
      }
    });
  }

  void _resetForNewRun() {
    setState(() {
      _state = RunState.searchingGps;
      _followUser = true;
      _route.clear();
      _startPoint = null;
      _distance = 0.0;
      _totalDistanceInMeters = 0.0;
      _elapsedRunTime = Duration.zero;
      _factsCount = 0;
      _lastFactTime = null;
      _lastFactIndices.clear();
      _lastCameraUpdate = null;
      _lastValidGpsTime = null;
      _smoothedPosition = null;
      _smoothedHeading = 0.0;
      _cachedAllSpokenIndices = null;
      _factsService.clearSessionState();
      _poiService.resetAnnouncedFlags();
      _currentCity = null;
      _spokenFactIndices.clear();
    });
    unawaited(_attemptToGetCurrentPosition());
  }

  @override
  Widget build(BuildContext context) {
    final currentRunTime = _getCurrentRunTime();
    final currentPace = _currentPace;
    final currentCalories = _calculateCalories().round();
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentCity ?? 'Определяем город...'),
        actions: [
          IconButton(
            icon: Icon(
              _musicMode == MusicMode.app ? Icons.music_note : Icons.library_music,
            ),
            onPressed: () {
              setState(() {
                _musicMode = _musicMode == MusicMode.app ? MusicMode.external : MusicMode.app;
              });
              _audio.playMusic(_musicMode);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (String choice) {
              if (choice == 'history') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HistoryScreen()),
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
              initialCenter: _lastSmoothedPosition ?? const LatLng(47.2313, 39.7233),
              initialZoom: 16,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.running_historian',
              ),
              if ((_state == RunState.running || _state == RunState.finished) && _route.isNotEmpty)
                PolylineLayer(polylines: [..._buildSpeedPolylines()]),
              if (_lastSmoothedPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _lastSmoothedPosition!,
                      width: 50,
                      height: 50,
                      child: Transform.rotate(
                        angle: _smoothedHeading * math.pi / 180,
                        child: const Icon(Icons.navigation, color: Colors.deepPurple, size: 28),
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
                        child: const Icon(Icons.flag, color: Colors.white, size: 24),
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
                        child: const Icon(Icons.fiber_manual_record, color: Colors.white, size: 16),
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
                      child: const Icon(Icons.location_pin, color: Colors.white, size: 24),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          if (_state == RunState.running || _state == RunState.paused)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.6),
                          blurRadius: 15,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            ScaleTransition(
                              scale: _distanceAnimation,
                              child: Text(
                                _distance.toStringAsFixed(2),
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'км',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildStatItem(
                              icon: Icons.access_time_filled_rounded,
                              value:
                                  '${currentRunTime.inMinutes.remainder(60).toString().padLeft(2, '0')}:${(currentRunTime.inSeconds.remainder(60)).toString().padLeft(2, '0')}',
                              label: 'Время',
                              color: Colors.blue.shade300,
                              fontSize: 18,
                            ),
                            _buildStatItem(
                              icon: Icons.speed_rounded,
                              value: currentPace,
                              label: 'Темп',
                              color: Colors.purple.shade300,
                              fontSize: 18,
                            ),
                            _buildStatItem(
                              icon: Icons.local_fire_department_rounded,
                              value: currentCalories.toString(),
                              label: 'Кал',
                              color: Colors.orange.shade300,
                              fontSize: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_state != RunState.init &&
                      _state != RunState.searchingGps &&
                      _state != RunState.countdown)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildAudioGuideWidget(),
                    ),
                ],
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
                        style: const TextStyle(fontSize: 20, color: Colors.white),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Stop', style: TextStyle(fontSize: 18)),
                      ),
                    ],
                  ),
                if (_state == RunState.finished)
                  ElevatedButton(
                    onPressed: _resetForNewRun,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(200, 60),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

// 🔑 ФИЛЬТР КАЛМАНА (ОПТИМИЗИРОВАН ДЛЯ ГОРОДСКИХ УСЛОВИЙ)
class KalmanLatLng {
  double qMetresPerSecond;
  double rMetres;
  double lat = 0.0;
  double lng = 0.0;
  double variance = -1;

  KalmanLatLng(this.qMetresPerSecond, this.rMetres);

  void reset() {
    variance = -1;
  }

  LatLng process(LatLng measurement, double accuracy, double dt) {
    if (variance < 0) {
      lat = measurement.latitude;
      lng = measurement.longitude;
      variance = accuracy * accuracy;
    } else {
      variance += dt * qMetresPerSecond * qMetresPerSecond;
      final k = variance / (variance + accuracy * accuracy);
      lat += k * (measurement.latitude - lat);
      lng += k * (measurement.longitude - lng);
      variance *= (1 - k);
    }
    return LatLng(lat, lng);
  }
}

void unawaited(Future<void> future) {}