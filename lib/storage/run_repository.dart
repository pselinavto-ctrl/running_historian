// lib/storage/run_repository.dart

import 'package:hive/hive.dart';
import '../domain/run_session.dart';
import '../domain/route_point.dart';

class RunRepository {
  static const String _sessionsBoxName = 'run_sessions';
  static const String _activeRouteBoxName = 'active_route';
  static const String _spokenFactsBoxName = 'spoken_facts';

  Box<RunSession> get _sessionsBox => Hive.box<RunSession>(_sessionsBoxName);
  Box<RoutePoint> get _activeRouteBox => Hive.box<RoutePoint>(_activeRouteBoxName);
  Box<List<int>> get _spokenFactsBox => Hive.box<List<int>>(_spokenFactsBoxName);

  Future<void> saveSession(RunSession session) async {
    await _sessionsBox.put(session.id, session);
    await _updateGlobalSpokenFacts(session.spokenFactIndices);
  }

  // ✅ РАБОЧИЙ МЕТОД УДАЛЕНИЯ
  Future<void> deleteSession(String id) async {
    if (_sessionsBox.containsKey(id)) {
      await _sessionsBox.delete(id);
    }
  }

  Future<List<RunSession>> getHistory() async {
    return _sessionsBox.values.toList();
  }

  Future<void> appendActivePoint(RoutePoint point) async {
    await _activeRouteBox.add(point);
  }

  Future<List<RoutePoint>> getActiveRoute() async {
    return _activeRouteBox.values.toList();
  }

  Future<void> clearActiveRoute() async {
    await _activeRouteBox.clear();
  }

  Future<List<int>> getAllSpokenFactIndices() async {
    final sessions = await getHistory();
    final allIndices = <int>{};

    for (final session in sessions) {
      allIndices.addAll(session.spokenFactIndices);
    }

    final global = _spokenFactsBox.get('global', defaultValue: <int>[]);
    // ✅ Безопасная обработка null и приведение типов
    if (global != null) {
      for (final item in global) {
        if (item is int) {
          allIndices.add(item);
        }
      }
    }

    return allIndices.toList();
  }

  Future<void> _updateGlobalSpokenFacts(List<int> newIndices) async {
    final current = _spokenFactsBox.get('global', defaultValue: <int>[]);
    final Set<int> updatedSet = <int>{};

    if (current != null) {
      for (final item in current) {
        if (item is int) {
          updatedSet.add(item);
        }
      }
    }

    updatedSet.addAll(newIndices);
    await _spokenFactsBox.put('global', updatedSet.toList());
  }

  Future<void> clearGlobalSpokenFacts() async {
    await _spokenFactsBox.delete('global');
  }

  Future<List<int>> getGlobalSpokenIndices() async {
    final data = _spokenFactsBox.get('global', defaultValue: <int>[]);
    final result = <int>[];
    if (data != null) {
      for (final item in data) {
        if (item is int) {
          result.add(item);
        }
      }
    }
    return result;
  }
}