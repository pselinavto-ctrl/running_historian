// lib/main.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart'; // ✅ Добавить импорт
import 'package:running_historian/ui/screens/run_screen.dart';
import 'package:running_historian/services/background_service.dart';
import 'package:running_historian/domain/route_point.dart'; // ✅ Импорт RoutePoint
import 'package:running_historian/domain/run_session.dart'; // ✅ Импорт RunSession

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ ИНИЦИАЛИЗАЦИЯ HIVE
  await Hive.initFlutter();
  // ✅ РЕГИСТРАЦИЯ АДАПТЕРОВ
  Hive.registerAdapter(RoutePointAdapter());
  Hive.registerAdapter(RunSessionAdapter()); // Если используете

  await Hive.openBox<RunSession>('run_sessions');
  await Hive.openBox<RoutePoint>('active_route');

  await initBackgroundService();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Running Historian',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const RunScreen(), // или другой стартовый экран
    );
  }
}