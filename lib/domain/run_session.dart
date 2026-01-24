import 'package:hive/hive.dart';
import 'route_point.dart'; // Импорт RoutePoint

part 'run_session.g.dart';

@HiveType(typeId: 1) // Убедитесь, что typeId уникален
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
  final List<RoutePoint> route; // ❗️Важно: использует RoutePoint

  // 👇 ОБНОВЛЕНО: список сказанных индексов
  @HiveField(6)
  final List<int> spokenFactIndices;

  // 👇 НОВОЕ: показанные POI в этой сессии
  @HiveField(7)
  final List<String> shownPoiIds;

  RunSession({
    required this.id,
    required this.date,
    required this.distance,
    required this.duration,
    required this.factsCount,
    required this.route,
    this.spokenFactIndices = const [],
    this.shownPoiIds = const [],
  });

  // 👇 ОБНОВЛЕНО: конструктор для обновления сказанных фактов и POI
  RunSession copyWith({
    List<int>? spokenFactIndices,
    List<String>? shownPoiIds,
  }) {
    return RunSession(
      id: id,
      date: date,
      distance: distance,
      duration: duration,
      factsCount: factsCount,
      route: route,
      spokenFactIndices: spokenFactIndices ?? this.spokenFactIndices,
      shownPoiIds: shownPoiIds ?? this.shownPoiIds,
    );
  }
}