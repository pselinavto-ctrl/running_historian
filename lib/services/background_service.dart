import 'dart:async';
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
  // ❌ УБРАНО: DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Position? last;

  // GPS
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 10,
    ),
  ).listen((position) {
    // 👇 ФИЛЬТРАЦИЯ В ФОНЕ (архитектурно правильно)
    if (position.accuracy > 25) return;

    if (last != null) {
      final d = Geolocator.distanceBetween(
        last!.latitude,
        last!.longitude,
        position.latitude,
        position.longitude,
      );
      if (d > 50) return;
    }

    last = position;

    service.invoke('locationUpdate', {
      'lat': position.latitude,
      'lon': position.longitude,
      'timestamp': position.timestamp?.toIso8601String(),
      'speed': position.speed,
    });
  });

  // TTS по таймеру
  Timer.periodic(const Duration(minutes: 2), (timer) {
    final randomIndex =
        DateTime.now().millisecondsSinceEpoch % kGeneralFacts.length;
    final fact = kGeneralFacts[randomIndex];
    service.invoke('speak', {
      'text': 'Интересный факт о Ростове-на-Дону: $fact',
    });
  });
}
