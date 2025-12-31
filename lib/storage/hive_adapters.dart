import 'package:hive/hive.dart';
import '../domain/run_session.dart';
import '../domain/route_point.dart';

void registerHiveAdapters() {
  Hive.registerAdapter(RoutePointAdapter());
  Hive.registerAdapter(RunSessionAdapter());
}