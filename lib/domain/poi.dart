import 'package:hive/hive.dart';

part 'poi.g.dart';

@HiveType(typeId: 4)
class Poi extends HiveObject {
  @HiveField(0) String id;
  @HiveField(1) String name;
  @HiveField(2) double lat;
  @HiveField(3) double lon;
  @HiveField(4) bool announced;

  Poi({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.announced = false,
  });
}