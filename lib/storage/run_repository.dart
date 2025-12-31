import 'package:hive/hive.dart';
import '../domain/run_session.dart';

class RunRepository {
  static final Box<RunSession> _box = Hive.box<RunSession>('runs');

  Future<void> saveSession(RunSession session) async {
    await _box.put(session.id, session);
  }

  List<RunSession> getHistory() {
    return _box.values.toList();
  }
}