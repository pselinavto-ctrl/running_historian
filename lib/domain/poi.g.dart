// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poi.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PoiAdapter extends TypeAdapter<Poi> {
  @override
  final int typeId = 4;

  @override
  Poi read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Poi(
      id: fields[0] as String,
      name: fields[1] as String,
      lat: fields[2] as double,
      lon: fields[3] as double,
      announced: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Poi obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.lat)
      ..writeByte(3)
      ..write(obj.lon)
      ..writeByte(4)
      ..write(obj.announced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PoiAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
