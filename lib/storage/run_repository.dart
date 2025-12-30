import 'package:hive/hive.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/domain/route_point.dart';

class RunRepository {
  final Box box = Hive.box('runs');

  Future<void> saveSession(RunSession session) async {
    await box.add({
      'id': session.id,
      'date': session.date.toIso8601String(),
      'distance': session.distance,
      'duration': session.duration,
      'factsCount': session.factsCount,
      'route': session.route.map((p) => p.toJson()).toList(),
    });
  }

  Future<List<RunSession>> getHistory() async {
    return box.values.cast<Map>().map((data) {
      return RunSession(
        id: data['id'],
        date: DateTime.parse(data['date']),
        distance: data['distance'].toDouble(),
        duration: data['duration'],
        factsCount: data['factsCount'],
        route: (data['route'] as List)
            .cast<Map<String, dynamic>>()
            .map((e) => RoutePoint.fromJson(e))
            .toList(),
      );
    }).toList();
  }
}
