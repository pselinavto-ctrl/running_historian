import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_historian/main.dart';
import 'package:running_historian/ui/screens/run_screen.dart';
import 'package:running_historian/services/background_service.dart';
import 'package:running_historian/services/location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('RunScreen Tests', () {
    // Инициализация сервисов
    setUpAll(() async {
      await initBackgroundService();
      await FlutterBackgroundService().configure(
        androidConfiguration: AndroidConfiguration(
          onStart: (service) => {},
          autoStart: false,
        ),
        iosConfiguration: IosConfiguration(
          onForeground: (service) => {},
        ),
      );
    });

    testWidgets('RunScreen создается без ошибок', (WidgetTester tester) async {
      // Подмена Geolocator
      GeolocatorPlatform.instance = GeolocatorPlatformMock();
      PermissionHandlerPlatform.instance = PermissionHandlerPlatformMock();

      await tester.pumpWidget(
        MaterialApp(
          home: RunScreen(),
        ),
      );

      // Ожидаем, что экран отобразится
      expect(find.byType(RunScreen), findsOneWidget);
      expect(find.text('Ростов-на-Дону'), findsOneWidget);
    });

    testWidgets('RunScreen отображает кнопку Start', (WidgetTester tester) async {
      GeolocatorPlatform.instance = GeolocatorPlatformMock();
      PermissionHandlerPlatform.instance = PermissionHandlerPlatformMock();

      await tester.pumpWidget(
        MaterialApp(
          home: RunScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Ожидаем, что кнопка Start отображается
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('Нажатие Start запускает тренировку', (WidgetTester tester) async {
      GeolocatorPlatform.instance = GeolocatorPlatformMock();
      PermissionHandlerPlatform.instance = PermissionHandlerPlatformMock();

      await tester.pumpWidget(
        MaterialApp(
          home: RunScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Нажимаем Start
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      // Проверяем, что отобразился обратный отсчёт
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('Пауза и возобновление работают', (WidgetTester tester) async {
      GeolocatorPlatform.instance = GeolocatorPlatformMock();
      PermissionHandlerPlatform.instance = PermissionHandlerPlatformMock();

      await tester.pumpWidget(
        MaterialApp(
          home: RunScreen(),
        ),
      );

      // Запускаем тренировку
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4)); // Ждём окончания отсчёта

      // Нажимаем Pause
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      // Проверяем, что отобразились кнопки Resume и Stop
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);

      // Нажимаем Resume
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      // Проверяем, что вернулись кнопки Pause
      expect(find.text('Pause'), findsOneWidget);
    });

    testWidgets('Стоп завершает тренировку', (WidgetTester tester) async {
      GeolocatorPlatform.instance = GeolocatorPlatformMock();
      PermissionHandlerPlatform.instance = PermissionHandlerPlatformMock();

      await tester.pumpWidget(
        MaterialApp(
          home: RunScreen(),
        ),
      );

      // Запускаем тренировку
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));

      // Нажимаем Pause
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      // Нажимаем Stop
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      // Проверяем, что отобразилась кнопка Новая тренировка
      expect(find.text('Новая тренировка'), findsOneWidget);
    });
  });
}

// Моки для Geolocator
class GeolocatorPlatformMock extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<Position> getCurrentPosition({
    LocationAccuracy? accuracy = LocationAccuracy.best,
    bool? forceAndroidLocationManager = false,
  }) async {
    return Position(
      latitude: 47.2313,
      longitude: 39.7233,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) {
    return Stream.fromIterable([
      Position(
        latitude: 47.2313,
        longitude: 39.7233,
        timestamp: DateTime.now(),
        accuracy: 10,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
    ]);
  }
}

// Моки для PermissionHandler
class PermissionHandlerPlatformMock extends PermissionHandlerPlatform {
  @override
  Future<PermissionStatus> requestPermission(Permission permission) async {
    return PermissionStatus.granted;
  }

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    return PermissionStatus.granted;
  }
}