import 'package:running_historian/domain/route_point.dart';

class RunSession {
  final String id;
  final DateTime date;
  final double distance;
  final int duration;
  final int factsCount;
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