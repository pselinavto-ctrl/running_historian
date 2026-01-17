import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_historian/main.dart';
import 'package:running_historian/ui/screens/run_screen.dart';
import 'package:running_historian/services/background_service.dart';
import 'package:running_historian/services/location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:running_historian/domain/route_point.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/domain/listened_fact.dart';

void main() {
  group('RunScreen Tests', () {
    // Инициализация сервисов (один раз для всех тестов)
    setUpAll(() async {
      // Инициализация Hive для тестов (обязательно!)
      TestWidgetsFlutterBinding.ensureInitialized();
      await Hive.initFlutter();
      
      // Регистрация адаптеров Hive
      Hive.registerAdapter(RoutePointAdapter());
      Hive.registerAdapter(RunSessionAdapter());
      Hive.registerAdapter(ListenedFactAdapter());
      
      // Открытие боксов Hive
      await Hive.openBox<RunSession>('run_sessions');
      await Hive.openBox<RoutePoint>('active_route');
      await Hive.openBox<List<Map<String, dynamic>>>('osm_cache');
      await Hive.openBox<List<int>>('spoken_facts');
      await Hive.openBox<ListenedFact>('listened_facts');
      
      // FlutterBackgroundService работает только на Android/iOS
      // В тестах на других платформах просто игнорируем ошибку
      try {
        await initBackgroundService();
      } catch (e) {
        // Сервис работает только на Android/iOS, игнорируем для тестов
        // на других платформах (Windows, macOS, Linux)
      }
    });

    // Настройка моков перед каждым тестом (убирает дублирование)
    setUp(() {
      GeolocatorPlatform.instance = GeolocatorPlatformMock();
      // PermissionHandler не мокируется напрямую, используется через Geolocator
    });

    // Очистка после каждого теста (опционально, но хорошая практика)
    tearDown(() {
      // Можно добавить очистку состояния, если нужно
    });

    testWidgets('RunScreen создается без ошибок', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RunScreen(),
        ),
      );

      // Ожидаем, что экран отобразится
      expect(find.byType(RunScreen), findsOneWidget);
      expect(find.text('Ростов-на-Дону'), findsOneWidget);
    });

    testWidgets('RunScreen отображает кнопку Start', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RunScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Ожидаем, что кнопка Start отображается
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('Нажатие Start запускает обратный отсчёт', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RunScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Нажимаем Start
      await tester.tap(find.text('Start'));
      await tester.pump(); // Обновляем UI один раз

      // Проверяем, что сначала отображается "3"
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsNothing);
      expect(find.text('1'), findsNothing);

      // Ждём 1 секунду и проверяем "2"
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('3'), findsNothing);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsNothing);

      // Ждём ещё 1 секунду и проверяем "1"
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('3'), findsNothing);
      expect(find.text('2'), findsNothing);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('Пауза и возобновление работают', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RunScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Запускаем тренировку
      await tester.tap(find.text('Start'));
      await tester.pump();
      
      // Ждём окончания обратного отсчёта (3 секунды)
      await tester.pump(const Duration(seconds: 4));

      // Ждём, пока UI стабилизируется
      await tester.pumpAndSettle();

      // Нажимаем Pause
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      // Проверяем, что отобразились кнопки Resume и Stop
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);

      // Нажимаем Resume
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      // Проверяем, что вернулась кнопка Pause
      expect(find.text('Pause'), findsOneWidget);
    });

    testWidgets('Стоп завершает тренировку', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RunScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Запускаем тренировку
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4)); // Ждём окончания отсчёта
      await tester.pumpAndSettle();

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
  Future<LocationPermission> checkPermission() async => LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.whileInUse;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<Position> getCurrentPosition({
    LocationAccuracy? accuracy = LocationAccuracy.best,
    bool? forceAndroidLocationManager = false,
    LocationSettings? locationSettings,
  }) async {
    return Position(
      latitude: 47.2313,
      longitude: 39.7233,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
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
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
    ]);
  }
}