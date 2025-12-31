import 'package:hive/hive.dart';
import 'route_point.dart';

part 'run_session.g.dart';

@HiveType(typeId: 2)
class RunSession {
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

  RunSession({
    required this.id,
    required this.date,
    required this.distance,
    required this.duration,
    required this.factsCount,
    required this.route,
  });
}