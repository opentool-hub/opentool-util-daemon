// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dao.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OpenToolServerDaoAdapter extends TypeAdapter<OpenToolServerDao> {
  @override
  final int typeId = 0;

  @override
  OpenToolServerDao read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OpenToolServerDao(
      id: fields[0] as String,
      name: fields[1] as String,
      file: fields[2] as String,
      host: fields[3] as String,
      port: fields[4] as int,
      prefix: fields[5] as String,
      apiKeys: (fields[6] as List?)?.cast<String>(),
      pid: fields[7] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, OpenToolServerDao obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.file)
      ..writeByte(3)
      ..write(obj.host)
      ..writeByte(4)
      ..write(obj.port)
      ..writeByte(5)
      ..write(obj.prefix)
      ..writeByte(6)
      ..write(obj.apiKeys)
      ..writeByte(7)
      ..write(obj.pid);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpenToolServerDaoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
