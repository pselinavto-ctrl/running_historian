// lib/storage/run_repository.dart
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/run_session.dart';
import '../domain/route_point.dart';

class RunRepository {
  static const String _sessionsBoxName = 'run_sessions';
  static const String _activeRouteBoxName = 'active_route';

  Future<Box<RunSession>> _getSessionsBox() async {
    // Регистрация адаптера не обязательна здесь, если она уже выполнена в main и background_service
    return Hive.openBox<RunSession>(_sessionsBoxName);
  }

  Future<Box<RoutePoint>> _getActiveRouteBox() async {
    // Регистрация адаптера не обязательна здесь, если она уже выполнена в main и background_service
    return Hive.openBox<RoutePoint>(_activeRouteBoxName);
  }

  Future<void> saveSession(RunSession session) async {
    final box = await _getSessionsBox();
    await box.put(session.id, session);
  }

  Future<List<RunSession>> getHistory() async {
    final box = await _getSessionsBox();
    return box.values.toList();
  }

  Future<void> appendActivePoint(RoutePoint point) async {
    final box = await _getActiveRouteBox();
    await box.add(point);
  }

  Future<List<RoutePoint>> getActiveRoute() async {
    final box = await _getActiveRouteBox();
    return box.values.toList();
  }

  Future<void> clearActiveRoute() async {
    final box = await _getActiveRouteBox();
    await box.clear();
  }

  Future<List<int>> getAllSpokenFactIndices() async {
    final sessions = await getHistory();
    final indices = <int>{};
    for (final session in sessions) {
      indices.addAll(session.spokenFactIndices);
    }
    return indices.toList();
  }
}