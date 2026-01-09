import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:running_historian/config/constants.dart';

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'running_historian_channel',
      initialNotificationTitle: 'Running Historian',
      initialNotificationContent: 'Аудиогид работает',
      foregroundServiceNotificationId: 777,
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  ui.DartPluginRegistrant.ensureInitialized();

  // Запрашиваем разрешения сразу в фоне
  await _requestPermissions();

  if (service is AndroidServiceInstance) {
    // 🔥 КРИТИЧЕСКИ ВАЖНО: вызвать setAsForegroundService() ДО выполнения других задач
    service.setAsForegroundService();

    // Установить информацию для уведомления (опционально, но желательно сразу)
    service.setForegroundNotificationInfo(
      title: "Running Historian",
      content: "Запись тренировки активна",
    );
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  _startLocationUpdates(service);
  _startFactTimer(service);
}

Future<void> _requestPermissions() async {
  LocationPermission permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever) {
    // Можно отправить уведомление пользователю
    print('Разрешение на геолокацию отклонено навсегда');
  }
}

void _startLocationUpdates(ServiceInstance service) {
  // 👇 КРИТИЧЕСКИ ВАЖНО: настройки именно для Android
  final locationSettings = AndroidSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 5,
    intervalDuration: const Duration(
      seconds: 1,
    ), // ИСПРАВЛЕНО: Duration вместо int
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: 'Running Historian',
      notificationText: 'Запись тренировки',
      enableWakeLock: true,
    ),
  );

  Geolocator.getPositionStream(locationSettings: locationSettings).listen(
    (position) {
      service.invoke('locationUpdate', {
        'lat': position.latitude,
        'lon': position.longitude,
        'speed': position.speed,
        'heading': position.heading ?? 0.0,
        'timestamp': position.timestamp?.toIso8601String(),
      });
    },
    onError: (error) {
      print('Ошибка фонового GPS: $error');
    },
  );
}

void _startFactTimer(ServiceInstance service) {
  Timer.periodic(const Duration(minutes: 2), (timer) {
    final randomIndex =
        DateTime.now().millisecondsSinceEpoch % kGeneralFacts.length;
    final fact = kGeneralFacts[randomIndex];
    service.invoke('speak', {
      'text': 'Интересный факт о Ростове-на-Дону: $fact',
    });
  });
}
