import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'storage/hive_adapters.dart';
import 'domain/run_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  registerHiveAdapters();
  await Hive.openBox<RunSession>('runs');

  runApp(const RunningHistorianApp());
}