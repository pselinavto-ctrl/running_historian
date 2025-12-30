import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

Future<void> initBackgroundService() async {
  await FlutterBackgroundService().configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

void onStart(ServiceInstance service) {
  Geolocator.getPositionStream().listen((pos) {
    service.invoke('location', {
      'lat': pos.latitude,
      'lon': pos.longitude,
    });
  });
}
