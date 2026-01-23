// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tile_meta.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TileMetaAdapter extends TypeAdapter<TileMeta> {
  @override
  final int typeId = 0;

  @override
  TileMeta read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TileMeta(
      key: fields[0] as String,
      sizeBytes: fields[1] as int,
      lastAccess: fields[2] as DateTime,
      createdAt: fields[3] as DateTime,
      z: fields[4] as int,
    );
  }

  @override
  void write(BinaryWriter writer, TileMeta obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.key)
      ..writeByte(1)
      ..write(obj.sizeBytes)
      ..writeByte(2)
      ..write(obj.lastAccess)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.z);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileMetaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
