import 'package:hive/hive.dart';

part 'fact.g.dart';

@HiveType(typeId: 2)
class Fact {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String text;

  @HiveField(2)
  final String type; // 'object' или 'general'

  @HiveField(3)
  final String? landmarkId; // для object-фактов

  @HiveField(4)
  final DateTime? consumedAt;

  @HiveField(5)
  final DateTime createdAt;

  Fact({
    required this.id,
    required this.text,
    required this.type,
    this.landmarkId,
    this.consumedAt,
    required this.createdAt,
  });

  bool get isConsumed => consumedAt != null;

  Fact copyWith({DateTime? consumedAt}) {
    return Fact(
      id: id,
      text: text,
      type: type,
      landmarkId: landmarkId,
      consumedAt: consumedAt,
      createdAt: createdAt,
    );
  }
}