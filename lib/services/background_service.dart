// lib/services/background_service.dart

import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:hive/hive.dart';
import 'package:geolocator/geolocator.dart';
import 'package:running_historian/domain/route_point.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:path_provider/path_provider.dart';

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true, // ← Достаточно этого для работы геолокации в фоне
      notificationChannelId: 'running_historian_channel',
      initialNotificationTitle: 'Running Historian',
      initialNotificationContent: 'Тренировка активна',
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Подписка на остановку
  service.on('stopService').listen((_) {
    print('[BG SERVICE] Received stop command');
    service.stopSelf();
  });

  // Подписка на старт тренировки — для сброса состояния
  service.on('startRun').listen((_) {
    print('[BG SERVICE] Run started — clearing route buffer');
    try {
      final box = Hive.box<RoutePoint>('active_route');
      box.clear();
    } catch (e) {
      print('[BG SERVICE] Error clearing route: $e');
    }
  });

  // Инициализация Hive в фоне
  try {
    final dir = await getApplicationDocumentsDirectory();
    Hive.init(dir.path);
    Hive.registerAdapter(RoutePointAdapter());
    Hive.registerAdapter(RunSessionAdapter());

    await Hive.openBox<RoutePoint>('active_route');
    await Hive.openBox<RunSession>('run_sessions');
    await Hive.openBox<List<int>>('spoken_facts');

    _startLocationUpdates(service);
  } catch (e, stack) {
    print('[BG SERVICE] Ошибка инициализации: $e\n$stack');
  }
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  return true;
}

void _startLocationUpdates(ServiceInstance service) {
  print('[BG SERVICE] Starting location stream (distanceFilter: 3m)...');
  
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3, // ← каждые 3 метра
    ),
  ).listen(
    (Position position) {
      print('[BG SERVICE] Got position: ${position.latitude}, ${position.longitude} | speed: ${position.speed} m/s');
      
      try {
        // Сохраняем в Hive
        final box = Hive.box<RoutePoint>('active_route');
        box.add(RoutePoint(
          lat: position.latitude,
          lon: position.longitude,
          timestamp: position.timestamp,
          speed: position.speed,
        ));

        // Отправляем в основное приложение
        service.invoke('locationUpdate', {
          'lat': position.latitude,
          'lon': position.longitude,
          'timestamp': position.timestamp.toIso8601String(),
          'heading': position.heading,
          'speed': position.speed,
        });
      } catch (e) {
        print('[BG SERVICE] Ошибка обработки точки: $e');
      }
    },
    onError: (error) {
      print('[BG SERVICE] Location stream error: $error');
      // Перезапуск потока через 5 секунд
      Future.delayed(Duration(seconds: 5), () {
        _startLocationUpdates(service);
      });
    },
    cancelOnError: false,
  );
}