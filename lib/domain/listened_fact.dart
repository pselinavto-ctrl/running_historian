import 'package:hive/hive.dart';
import 'package:running_historian/services/guide_engine.dart'; // 👈 ДОБАВЛЯЕМ ИМПОРТ

part 'listened_fact.g.dart';

enum FactType { poi, context, general }

@HiveType(typeId: 10)
class ListenedFact {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final DateTime listenedAt;
  
  @HiveField(2)
  final String text;
  
  @HiveField(3)
  final String? poiId;
  
  @HiveField(4)
  final String? poiName;
  
  @HiveField(5)
  final double? distanceKm;
  
  @HiveField(6)
  final Duration? runTime;
  
  @HiveField(7)
  final int factTypeIndex;
  
  @HiveField(8)
  final String? city;
  
  ListenedFact({
    required this.id,
    required this.listenedAt,
    required this.text,
    this.poiId,
    this.poiName,
    this.distanceKm,
    this.runTime,
    required this.factTypeIndex,
    this.city,
  });
  
  FactType get factType => FactType.values[factTypeIndex];
  
  factory ListenedFact.fromSpeechItem({
    required SpeechItem speech, // 👈 Теперь импорт есть
    required double distanceKm,
    required Duration runTime,
    String? city,
    String? poiName,
  }) {
    final id = '${DateTime.now().microsecondsSinceEpoch}_${speech.poiId ?? 'general'}';
    
    int convertType(SpeechType speechType) { // 👈 Теперь импорт есть
      switch (speechType) {
        case SpeechType.poi:
          return FactType.poi.index;
        case SpeechType.context:
          return FactType.context.index;
        case SpeechType.general:
          return FactType.general.index;
      }
    }
    
    return ListenedFact(
      id: id,
      listenedAt: DateTime.now(),
      text: speech.text,
      poiId: speech.poiId,
      poiName: poiName,
      distanceKm: distanceKm,
      runTime: runTime,
      factTypeIndex: convertType(speech.type),
      city: city,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'listenedAt': listenedAt.toIso8601String(),
      'text': text,
      'poiId': poiId,
      'poiName': poiName,
      'distanceKm': distanceKm,
      'runTimeSeconds': runTime?.inSeconds,
      'factType': factType.name,
      'city': city,
    };
  }
}