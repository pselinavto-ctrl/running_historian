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
      isForegroundMode: true,
      // 👇 ОБЯЗАТЕЛЬНО: канал и текст
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
    service.stopSelf();
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
    print('Ошибка фона: $e\n$stack');
  }
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  return true;
}

void _startLocationUpdates(ServiceInstance service) {
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
    ),
  ).listen((Position position) {
    try {
      final box = Hive.box<RoutePoint>('active_route');
      box.add(RoutePoint(
        lat: position.latitude,
        lon: position.longitude,
        timestamp: position.timestamp,
        speed: position.speed,
      ));

      service.invoke('locationUpdate', {
        'lat': position.latitude,
        'lon': position.longitude,
        'timestamp': position.timestamp.toIso8601String(),
        'heading': position.heading,
        'speed': position.speed,
      });
    } catch (e) {
      print('Ошибка сохранения точки: $e');
    }
  });
}