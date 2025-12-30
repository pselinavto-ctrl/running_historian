import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'storage/hive_adapters.dart';
// УБРАНО: import 'services/background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  registerHiveAdapters();
  await Hive.openBox('runs');

  // УБРАНО: await initBackgroundService();

  runApp(const RunningHistorianApp());
}
