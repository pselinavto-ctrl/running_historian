// lib/domain/fact.dart
import 'package:hive/hive.dart';

part 'fact.g.dart';

@HiveType(typeId: 2)
class Fact {
  @HiveField(0) final String id;
  @HiveField(1) final String text;
  @HiveField(2) final String type; // 'general', 'object', 'city'
  @HiveField(3) final String? landmarkId;
  @HiveField(4) final DateTime? consumedAt;
  @HiveField(5) final DateTime createdAt;

  // 🔹 НОВОЕ:
  @HiveField(6) final String? city;
  @HiveField(7) final String? region;

  Fact({
    required this.id,
    required this.text,
    required this.type,
    this.landmarkId,
    this.consumedAt,
    required this.createdAt,
    this.city,
    this.region,
  });

  bool get isConsumed => consumedAt != null;

  Fact copyWith({DateTime? consumedAt}) {
    return Fact(
      id: id,
      text: text,
      type: type,
      landmarkId: landmarkId,
      consumedAt: consumedAt ?? this.consumedAt,
      createdAt: createdAt,
      city: city,
      region: region,
    );
  }
}