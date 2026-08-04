// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dao.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InternalServerDaoAdapter extends TypeAdapter<InternalServerDao> {
  @override
  final int typeId = 0;

  @override
  InternalServerDao read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InternalServerDao(
      id: fields[0] as String,
      file: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, InternalServerDao obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.file);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InternalServerDaoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ServerDaoAdapter extends TypeAdapter<ServerDao> {
  @override
  final int typeId = 1;

  @override
  ServerDao read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ServerDao(
      id: fields[0] as String,
      alias: fields[1] as String,
      registry: fields[2] as String,
      namespace: fields[3] as String?,
      name: fields[4] as String,
      version: fields[5] as String?,
      internalId: fields[6] as String,
      artifactId: fields[7] as String?,
      versionDigest: fields[8] as String?,
      artifactDigest: fields[9] as String?,
      artifactSize: fields[10] as int?,
      platformOs: fields[11] as String?,
      platformArch: fields[12] as String?,
      platformAbi: fields[13] as String?,
      installedAt: fields[14] as DateTime?,
      artifactMediaType: fields[15] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ServerDao obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.alias)
      ..writeByte(2)
      ..write(obj.registry)
      ..writeByte(3)
      ..write(obj.namespace)
      ..writeByte(4)
      ..write(obj.name)
      ..writeByte(5)
      ..write(obj.version)
      ..writeByte(6)
      ..write(obj.internalId)
      ..writeByte(7)
      ..write(obj.artifactId)
      ..writeByte(8)
      ..write(obj.versionDigest)
      ..writeByte(9)
      ..write(obj.artifactDigest)
      ..writeByte(10)
      ..write(obj.artifactSize)
      ..writeByte(11)
      ..write(obj.platformOs)
      ..writeByte(12)
      ..write(obj.platformArch)
      ..writeByte(13)
      ..write(obj.platformAbi)
      ..writeByte(14)
      ..write(obj.installedAt)
      ..writeByte(15)
      ..write(obj.artifactMediaType);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerDaoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ToolDaoAdapter extends TypeAdapter<ToolDao> {
  @override
  final int typeId = 2;

  @override
  ToolDao read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ToolDao(
      id: fields[0] as String,
      alias: fields[1] as String,
      tag: fields[2] as String,
      host: fields[3] as String,
      port: fields[4] as int,
      apiKey: fields[5] as String,
      status: fields[6] as String,
      serverId: fields[8] as String?,
      extraCmds: (fields[7] as List?)?.cast<String>(),
      serverRegistry: fields[9] as String?,
      serverRepo: fields[10] as String?,
      serverName: fields[11] as String?,
      serverTag: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ToolDao obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.alias)
      ..writeByte(2)
      ..write(obj.tag)
      ..writeByte(3)
      ..write(obj.host)
      ..writeByte(4)
      ..write(obj.port)
      ..writeByte(5)
      ..write(obj.apiKey)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.extraCmds)
      ..writeByte(8)
      ..write(obj.serverId)
      ..writeByte(9)
      ..write(obj.serverRegistry)
      ..writeByte(10)
      ..write(obj.serverRepo)
      ..writeByte(11)
      ..write(obj.serverName)
      ..writeByte(12)
      ..write(obj.serverTag);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolDaoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ApiKeyDaoAdapter extends TypeAdapter<ApiKeyDao> {
  @override
  final int typeId = 3;

  @override
  ApiKeyDao read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ApiKeyDao(
      id: fields[0] as String,
      name: fields[1] as String,
      apiKey: fields[2] as String,
      createdAt: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ApiKeyDao obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.apiKey)
      ..writeByte(3)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiKeyDaoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
