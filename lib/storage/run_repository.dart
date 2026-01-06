import 'package:hive/hive.dart';
import '../domain/run_session.dart';

class RunRepository {
  final Box<RunSession> box = Hive.box<RunSession>('runs');

  Future<void> saveSession(RunSession session) async {
    await box.put(session.id, session); // теперь сохраняет spokenFactIndices
  }

  List<RunSession> getHistory() {
    return box.values.toList();
  }

  // 👇 НОВОЕ: получить все сказанные индексы
  Set<int> getAllSpokenFactIndices() {
    final allIndices = <int>{};
    for (final session in box.values) {
      allIndices.addAll(session.spokenFactIndices);
    }
    return allIndices;
  }
}