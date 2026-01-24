import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:running_historian/ui/screens/welcome_screen.dart';
import 'package:running_historian/ui/screens/run_screen.dart';
import 'package:running_historian/services/background_service.dart';
import 'package:running_historian/domain/route_point.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/domain/listened_fact.dart';

// 👇 ДОБАВЛЕН ИМПОРТ Fact
import 'package:running_historian/domain/fact.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ ИНИЦИАЛИЗАЦИЯ HIVE
  await Hive.initFlutter();

  // ✅ РЕГИСТРАЦИЯ АДАПТЕРОВ
  Hive.registerAdapter(RoutePointAdapter());
  Hive.registerAdapter(RunSessionAdapter());
  Hive.registerAdapter(ListenedFactAdapter());
  // 👇 ДОБАВЛЕНА РЕГИСТРАЦИЯ FactAdapter
  Hive.registerAdapter(FactAdapter());

  // ✅ ОТКРЫТИЕ БОКСОВ
  await Hive.openBox<RunSession>('run_sessions');
  await Hive.openBox<RoutePoint>('active_route');
  await Hive.openBox<List<Map<String, dynamic>>>('osm_cache');
  await Hive.openBox<List<int>>('spoken_facts');
  await Hive.openBox<ListenedFact>('listened_facts');
  // 👇 ДОБАВЛЕНО ОТКРЫТИЕ БОКСА ДЛЯ ФАКТОВ
  await Hive.openBox<Fact>('facts');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Running Historian',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        fontFamily: 'Inter',
      ),
      home: const WelcomeScreen(),
    );
  }
}