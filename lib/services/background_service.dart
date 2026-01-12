// lib/services/background_service.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:running_historian/config/constants.dart';
import 'package:running_historian/storage/run_repository.dart';
import 'package:running_historian/domain/route_point.dart';
import 'package:hive_flutter/hive_flutter.dart'; // Импорт Hive

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, // или true, если нужно автостартовать
      isForegroundMode: true,
      notificationChannelId: 'running_historian_channel',
      initialNotificationTitle: 'Running Historian',
      initialNotificationContent: 'Аудиогид работает',
      foregroundServiceNotificationId: 777,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  ui.DartPluginRegistrant.ensureInitialized();

  // 🔥 КРИТИЧЕСКИ ВАЖНО: вызвать setAsForegroundService() СРАЗУ ЖЕ
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();

    // Установить информацию для уведомления (опционально, но желательно сразу)
    service.setForegroundNotificationInfo(
      title: "Running Historian",
      content: "Запись тренировки активна",
    );
  }

  // --- ВСЁ, ЧТО НИЖЕ, МОЖЕТ БЫТЬ АСИНХРОННЫМ ---
  // (но не должно блокировать выполнение основного потока сервиса надолго)

  // 1. Инициализация Hive (теперь после setAsForegroundService)
  await Hive.initFlutter();

  // 2. Регистрация адаптеров (теперь после setAsForegroundService)
  Hive.registerAdapter(RoutePointAdapter());
  // Hive.registerAdapter(RunSessionAdapter()); // Если используете

  // 3. Запрашиваем разрешения (теперь после setAsForegroundService)
  await _requestPermissions();

  // 4. Подписываемся на остановку (теперь после setAsForegroundService)
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 5. Запускаем логику (теперь после setAsForegroundService)
  _startLocationUpdates(service);
  _startFactTimer(service);
}

Future<void> _requestPermissions() async {
  LocationPermission permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever) {
    print('Разрешение на геолокацию отклонено навсегда');
  }
}

void _startLocationUpdates(ServiceInstance service) {
  final locationSettings = AndroidSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 5,
    intervalDuration: const Duration(seconds: 1),
    // ❗️ВАЖНО: используем ForegroundNotificationConfig из flutter_background_service_android
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: 'Running Historian',
      notificationText: 'Запись тренировки',
      enableWakeLock: true,
    ),
  );

  Geolocator.getPositionStream(locationSettings: locationSettings)
      .listen((position) async {
    final routePoint = RoutePoint(
      lat: position.latitude,
      lon: position.longitude,
      timestamp: position.timestamp ?? DateTime.now(),
      speed: position.speed,
    );

    // ✅ СОХРАНЯЕМ ТОЧКУ В Hive через RunRepository
    await RunRepository().appendActivePoint(routePoint);

    // ✅ ОБЯЗАТЕЛЬНО: отправляем данные в UI для реального времени
    service.invoke('locationUpdate', {
      'lat': position.latitude,
      'lon': position.longitude,
      'timestamp': position.timestamp?.toIso8601String(), // для сериализации
      'speed': position.speed,
      'heading': position.heading, // если доступно
    });
  }, onError: (error) {
    print('Ошибка фонового GPS: $error');
  });
}

void _startFactTimer(ServiceInstance service) {
  Timer.periodic(const Duration(minutes: 2), (timer) {
    final randomIndex = DateTime.now().millisecondsSinceEpoch % kGeneralFacts.length;
    final fact = kGeneralFacts[randomIndex];
    service.invoke('speak', {
      'text': 'Интересный факт о Ростове-на-Дону: $fact',
    });
  });
}