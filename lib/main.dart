// lib/main.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:running_historian/ui/screens/welcome_screen.dart';
import 'package:running_historian/domain/route_point.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/domain/listened_fact.dart';
import 'package:running_historian/domain/fact.dart';
import 'package:running_historian/services/fact_bank_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  Hive.registerAdapter(RoutePointAdapter());
  Hive.registerAdapter(RunSessionAdapter());
  Hive.registerAdapter(ListenedFactAdapter());
  Hive.registerAdapter(FactAdapter());

  await Hive.openBox<RunSession>('run_sessions');
  await Hive.openBox<RoutePoint>('active_route');
  await Hive.openBox<List<Map<String, dynamic>>>('osm_cache');
  await Hive.openBox<List<int>>('spoken_facts');
  await Hive.openBox<ListenedFact>('listened_facts');
  await Hive.openBox<Fact>('facts');

  runApp(const MyApp());

  // 🔥 ФОН: первичное наполнение
  unawaited(_preloadFacts());
}

Future<void> _preloadFacts() async {
  final service = FactBankService();
  await service.init();
  // Инициализация без пополнения — факты подгружаются при старте пробежки
}

void unawaited(Future<void> future) {}

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