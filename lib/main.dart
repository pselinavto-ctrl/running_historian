import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart'; // 👈 Для Hive.openBox
import 'package:running_historian/ui/screens/welcome_screen.dart'; // 👈 ИМПОРТ ДОБАВЛЕН
import 'package:running_historian/ui/screens/run_screen.dart';
import 'package:running_historian/services/background_service.dart';
import 'package:running_historian/domain/route_point.dart';
import 'package:running_historian/domain/run_session.dart';
// 👇 ИМПОРТ НОВОЙ СУЩНОСТИ
import 'package:running_historian/domain/listened_fact.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ ИНИЦИАЛИЗАЦИЯ HIVE
  await Hive.initFlutter();

  // ✅ РЕГИСТРАЦИЯ АДАПТЕРОВ
  Hive.registerAdapter(RoutePointAdapter());
  Hive.registerAdapter(RunSessionAdapter());
  Hive.registerAdapter(ListenedFactAdapter()); // 👈 РЕГИСТРИРУЕМ НОВЫЙ АДАПТЕР

  // ✅ ОТКРЫТИЕ БОКСОВ
  await Hive.openBox<RunSession>('run_sessions');
  await Hive.openBox<RoutePoint>('active_route');
  // ❗️Предполагаем, что 'osm_cache' и 'spoken_facts' используются глобально
  await Hive.openBox<List<Map<String, dynamic>>>('osm_cache');
  await Hive.openBox<List<int>>('spoken_facts');
  await Hive.openBox<ListenedFact>('listened_facts'); // 👈 ОТКРЫВАЕМ НОВЫЙ БОКС

  // ⚠️ НЕ запускайте сервис здесь
  // await initBackgroundService();

  runApp(const MyApp());
  
  // ⚠️ Запускайте сервис ПОСЛЕ runApp
  // await initBackgroundService();
  // final service = FlutterBackgroundService();
  // await service.startService();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Running Historian',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple, // 👈 Поменял цвет для стиля
        fontFamily: 'Inter', // 👈 Можно подключить шрифт позже
      ),
      home: const WelcomeScreen(), // 👈 ТЕПЕРЬ ЗАСТАВКА ПЕРВАЯ!
    );
  }
}