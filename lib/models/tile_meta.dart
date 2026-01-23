// lib/models/tile_meta.dart
import 'package:hive/hive.dart';

part 'tile_meta.g.dart'; // Этот файл сгенерируется автоматически

@HiveType(typeId: 0) // Уникальный typeId для Hive
class TileMeta extends HiveObject {
  @HiveField(0)
  final String key; // provider_z_x_y

  @HiveField(1)
  final int sizeBytes;

  @HiveField(2)
  final DateTime lastAccess;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  final int z;

  TileMeta({
    required this.key,
    required this.sizeBytes,
    required this.lastAccess,
    required this.createdAt,
    required this.z,
  });

  Map<String, dynamic> toMap() => {
        'key': key,
        'sizeBytes': sizeBytes,
        'lastAccess': lastAccess.millisecondsSinceEpoch,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'z': z,
      };

  static TileMeta fromMap(Map<dynamic, dynamic> map) => TileMeta(
        key: map['key'] as String,
        sizeBytes: map['sizeBytes'] as int,
        lastAccess: DateTime.fromMillisecondsSinceEpoch(map['lastAccess'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
        z: map['z'] as int,
      );
}