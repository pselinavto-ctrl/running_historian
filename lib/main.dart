import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'storage/hive_adapters.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appDir = await getApplicationDocumentsDirectory();
  final hivePath = path.join(appDir.path, 'hive');

  final hiveDir = Directory(hivePath);
  if (!hiveDir.existsSync()) {
    await hiveDir.create(recursive: true);
  }

  Hive.init(hivePath);

  registerHiveAdapters();
  await Hive.openBox('runs');

  runApp(const RunningHistorianApp());
}