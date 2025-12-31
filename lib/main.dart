import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'storage/hive_adapters.dart';
import 'domain/run_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(dir.path);

  registerHiveAdapters();

  await Hive.openBox<RunSession>('runs');

  runApp(const RunningHistorianApp());
}