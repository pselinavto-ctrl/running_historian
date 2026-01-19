// lib/services/background_service.dart
import 'dart:async';
import 'dart:ui' as ui;
// ❌ УБРАНО: import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
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
      autoStart: false,
      isForegroundMode: false, // ❗️ВАЖНО: isForegroundMode = false
      // ❌ УБРАНО: notificationChannelId, initialNotificationTitle, и т.д.
      // foregroundServiceNotificationId: 777, // Не нужно
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // 1. ОБЯЗАТЕЛЬНО САМОЕ ПЕРВОЕ: Инициализация Dart для плагинов
  ui.DartPluginRegistrant.ensureInitialized();

  // 2. НЕ ВЫЗЫВАЕМ setAsForegroundService() НИКОГДА!
  // if (service is AndroidServiceInstance) {
  //   service.setAsForegroundService();
  //   service.setForegroundNotificationInfo(...);
  // }

  // 3. ЗАПУСК ОСНОВНОЙ ЛОГИКИ В ОТДЕЛЬНОЙ "МИКРО-ЗАДАЧЕ", чтобы не блокировать поток
  Future.microtask(() async {
    await _initializeService(service);
  });
}

// ВСЮ тяжелую инициализацию выносим в отдельную асинхронную функцию
Future<void> _initializeService(ServiceInstance service) async {
  try {
    print("DEBUG: _initializeService started"); // Лог для отладки

    // 3.1. Инициализация Hive (может быть медленной)
    await Hive.initFlutter();
    Hive.registerAdapter(RoutePointAdapter());
    // Hive.registerAdapter(RunSessionAdapter()); // Если используете

    print("DEBUG: Hive initialized and adapters registered"); // Лог для отладки

    // 3.2. Запрос разрешений (может показывать системный диалог!)
    final bool hasPermission = await _requestPermissions();
    if (!hasPermission) {
      print("DEBUG: Permissions not granted, stopping service logic"); // Лог для отладки
      // Если нет разрешений, возможно, нужно остановить сервис или уведомить
      service.invoke('permissionDenied');
      // service.stopSelf(); // Опционально
      return;
    }

    print("DEBUG: Permissions granted"); // Лог для отладки

    // 3.3. Подписываемся на остановку (после инициализации)
    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    print("DEBUG: Stop listener added"); // Лог для отладки

    // 3.5. Запускаем фоновые процессы
    _startLocationUpdates(service);
    _startFactTimer(service);

    print("DEBUG: Location updates and fact timer started"); // Лог для отладки

  } catch (e, stack) {
    // КРИТИЧЕСКИ ВАЖНО: Логируем любую ошибку при инициализации
    print("FATAL: Ошибка инициализации фонового сервиса: $e, $stack");
    // Если сервис упал здесь, он перезапустится системой (autoStart: true),
    // но ошибка в логах поможет понять причину.
  }
}

Future<bool> _requestPermissions() async {
  LocationPermission permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    print("DEBUG: Requesting permission"); // Лог для отладки
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever) {
    print('Разрешение на геолокацию отклонено навсегда');
    return false;
  }

  return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
}

void _startLocationUpdates(ServiceInstance service) {
  // Проверяем разрешения перед запуском потока (хотя они уже проверены, но на всякий случай)
  Geolocator.isLocationServiceEnabled().then((enabled) {
    if (!enabled) {
      print("DEBUG: Location service is disabled");
      return;
    }

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 1),
      // ❗️ВАЖНО: ИСПОЛЬЗУЕМ foregroundNotificationConfig из flutter_background_service_android ТОЛЬКО ДЛЯ GEOLOCATOR!
      // Но! flutter_background_service_android не должен использоваться в изоляте сервиса!
      // Поэтому, мы НЕ ПЕРЕДАЕМ foregroundNotificationConfig сюда.
      // Geolocator сам создаст уведомление для своего ForegroundService.
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