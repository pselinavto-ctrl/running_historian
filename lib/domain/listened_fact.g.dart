// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listened_fact.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ListenedFactAdapter extends TypeAdapter<ListenedFact> {
  @override
  final int typeId = 10;

  @override
  ListenedFact read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ListenedFact(
      id: fields[0] as String,
      listenedAt: fields[1] as DateTime,
      text: fields[2] as String,
      poiId: fields[3] as String?,
      poiName: fields[4] as String?,
      distanceKm: fields[5] as double?,
      runTime: fields[6] as Duration?,
      factTypeIndex: fields[7] as int,
      city: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ListenedFact obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.listenedAt)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.poiId)
      ..writeByte(4)
      ..write(obj.poiName)
      ..writeByte(5)
      ..write(obj.distanceKm)
      ..writeByte(6)
      ..write(obj.runTime)
      ..writeByte(7)
      ..write(obj.factTypeIndex)
      ..writeByte(8)
      ..write(obj.city);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListenedFactAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
