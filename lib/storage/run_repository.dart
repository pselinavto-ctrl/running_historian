import 'package:hive_flutter/hive_flutter.dart';
import '../domain/run_session.dart';
import '../domain/route_point.dart';

class RunRepository {
  static const String _sessionsBoxName = 'run_sessions';
  static const String _activeRouteBoxName = 'active_route';
  static const String _spokenFactsBoxName = 'spoken_facts';

  Future<Box<RunSession>> _getSessionsBox() async {
    return Hive.openBox<RunSession>(_sessionsBoxName);
  }

  Future<Box<RoutePoint>> _getActiveRouteBox() async {
    return Hive.openBox<RoutePoint>(_activeRouteBoxName);
  }

  Future<Box<List<int>>> _getSpokenFactsBox() async {
    return Hive.openBox<List<int>>(_spokenFactsBoxName);
  }

  Future<void> saveSession(RunSession session) async {
    final box = await _getSessionsBox();
    await box.put(session.id, session);

    // ОБНОВЛЯЕМ ГЛОБАЛЬНЫЙ БАНК
    await _updateGlobalSpokenFacts(session.spokenFactIndices);
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

  // Загрузка ВСЕХ прослушанных индексов
  Future<List<int>> getAllSpokenFactIndices() async {
    final sessions = await getHistory();
    final allIndices = <int>{};

    for (final session in sessions) {
      allIndices.addAll(session.spokenFactIndices);
    }

    // Добавляем из глобального бокса
    final globalBox = await _getSpokenFactsBox();
    final globalIndices = globalBox.get('global', defaultValue: <int>[]);
    
    // ИСПРАВЛЕНИЕ 1: Явное приведение типа и проверка
    if (globalIndices != null) {
      allIndices.addAll(globalIndices);
    }

    return allIndices.toList();
  }

  // Обновление глобального банка
  Future<void> _updateGlobalSpokenFacts(List<int> newIndices) async {
    final box = await _getSpokenFactsBox();
    final current = box.get('global', defaultValue: <int>[]);
    
    // ИСПРАВЛЕНИЕ 2: Проверка на null перед spread оператором
    final Set<int> updatedSet = <int>{};
    
    if (current != null) {
      updatedSet.addAll(current);
    }
    
    updatedSet.addAll(newIndices);
    
    await box.put('global', updatedSet.toList());
  }

  // Очистка глобального банка
  Future<void> clearGlobalSpokenFacts() async {
    final box = await _getSpokenFactsBox();
    await box.clear();
  }
  
  // 👇 НОВЫЙ МЕТОД: Загрузка ТОЛЬКО глобального банка (для быстрого доступа)
  Future<List<int>> getGlobalSpokenIndices() async {
    final box = await _getSpokenFactsBox();
    final indices = box.get('global', defaultValue: <int>[]);
    return indices ?? <int>[];
  }
}