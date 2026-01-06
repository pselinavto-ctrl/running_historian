import 'package:hive/hive.dart';
import 'route_point.dart';

part 'run_session.g.dart';

@HiveType(typeId: 2)
class RunSession extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime date;

  @HiveField(2)
  final double distance;

  @HiveField(3)
  final int duration;

  @HiveField(4)
  final int factsCount;

  @HiveField(5)
  final List<RoutePoint> route;

  // 👇 НОВОЕ: список сказанных индексов
  @HiveField(6)
  final List<int> spokenFactIndices;

  RunSession({
    required this.id,
    required this.date,
    required this.distance,
    required this.duration,
    required this.factsCount,
    required this.route,
    this.spokenFactIndices = const [],
  });

  // 👇 НОВОЕ: конструктор для обновления сказанных фактов
  RunSession copyWith({List<int>? spokenFactIndices}) {
    return RunSession(
      id: id,
      date: date,
      distance: distance,
      duration: duration,
      factsCount: factsCount,
      route: route,
      spokenFactIndices: spokenFactIndices ?? this.spokenFactIndices,
    );
  }
}