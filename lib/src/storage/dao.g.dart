// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dao.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

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

class ArtifactDaoAdapter extends TypeAdapter<ArtifactDao> {
  @override
  final int typeId = 4;

  @override
  ArtifactDao read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ArtifactDao(
      digest: fields[0] as String,
      size: fields[1] as int,
      mediaType: fields[2] as String,
      platformOs: fields[3] as String,
      platformArch: fields[4] as String,
      platformAbi: fields[5] as String,
      filePath: fields[6] as String,
      manifestName: fields[7] as String,
      manifestVersion: fields[8] as String,
      verifiedAt: fields[9] as DateTime,
      createdAt: fields[10] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ArtifactDao obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.digest)
      ..writeByte(1)
      ..write(obj.size)
      ..writeByte(2)
      ..write(obj.mediaType)
      ..writeByte(3)
      ..write(obj.platformOs)
      ..writeByte(4)
      ..write(obj.platformArch)
      ..writeByte(5)
      ..write(obj.platformAbi)
      ..writeByte(6)
      ..write(obj.filePath)
      ..writeByte(7)
      ..write(obj.manifestName)
      ..writeByte(8)
      ..write(obj.manifestVersion)
      ..writeByte(9)
      ..write(obj.verifiedAt)
      ..writeByte(10)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactDaoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ServerDaoAdapter extends TypeAdapter<ServerDao> {
  @override
  final int typeId = 5;

  @override
  ServerDao read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ServerDao(
      id: fields[0] as String,
      alias: fields[1] as String,
      namespace: fields[2] as String,
      name: fields[3] as String,
      version: fields[4] as String,
      artifactDigest: fields[5] as String,
      sourceKind: fields[6] as String,
      sourceKey: fields[7] as String,
      registry: fields[8] as String?,
      versionDigest: fields[9] as String?,
      hubArtifactId: fields[10] as String?,
      builtinBundleFamily: fields[11] as String?,
      builtinBundleId: fields[12] as String?,
      builtinKey: fields[13] as String?,
      protected: fields[14] as bool,
      managedBy: fields[15] as String,
      state: fields[16] as String,
      createdAt: fields[17] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ServerDao obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.alias)
      ..writeByte(2)
      ..write(obj.namespace)
      ..writeByte(3)
      ..write(obj.name)
      ..writeByte(4)
      ..write(obj.version)
      ..writeByte(5)
      ..write(obj.artifactDigest)
      ..writeByte(6)
      ..write(obj.sourceKind)
      ..writeByte(7)
      ..write(obj.sourceKey)
      ..writeByte(8)
      ..write(obj.registry)
      ..writeByte(9)
      ..write(obj.versionDigest)
      ..writeByte(10)
      ..write(obj.hubArtifactId)
      ..writeByte(11)
      ..write(obj.builtinBundleFamily)
      ..writeByte(12)
      ..write(obj.builtinBundleId)
      ..writeByte(13)
      ..write(obj.builtinKey)
      ..writeByte(14)
      ..write(obj.protected)
      ..writeByte(15)
      ..write(obj.managedBy)
      ..writeByte(16)
      ..write(obj.state)
      ..writeByte(17)
      ..write(obj.createdAt);
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
  final int typeId = 6;

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
      extraCmds: (fields[7] as List?)?.cast<String>(),
      serverId: fields[8] as String?,
      materializedArtifactDigest: fields[9] as String?,
      serverRegistry: fields[10] as String?,
      serverNamespace: fields[11] as String?,
      serverName: fields[12] as String?,
      serverVersion: fields[13] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ToolDao obj) {
    writer
      ..writeByte(14)
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
      ..write(obj.materializedArtifactDigest)
      ..writeByte(10)
      ..write(obj.serverRegistry)
      ..writeByte(11)
      ..write(obj.serverNamespace)
      ..writeByte(12)
      ..write(obj.serverName)
      ..writeByte(13)
      ..write(obj.serverVersion);
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

class ArtifactOperationDaoAdapter extends TypeAdapter<ArtifactOperationDao> {
  @override
  final int typeId = 7;

  @override
  ArtifactOperationDao read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ArtifactOperationDao(
      id: fields[0] as String,
      type: fields[1] as String,
      stage: fields[2] as String,
      tempPath: fields[3] as String?,
      digest: fields[4] as String?,
      serverId: fields[5] as String?,
      sourceKind: fields[6] as String?,
      sourceKey: fields[7] as String?,
      payloadJson: fields[8] as String?,
      createdAt: fields[9] as DateTime,
      updatedAt: fields[10] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ArtifactOperationDao obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.stage)
      ..writeByte(3)
      ..write(obj.tempPath)
      ..writeByte(4)
      ..write(obj.digest)
      ..writeByte(5)
      ..write(obj.serverId)
      ..writeByte(6)
      ..write(obj.sourceKind)
      ..writeByte(7)
      ..write(obj.sourceKey)
      ..writeByte(8)
      ..write(obj.payloadJson)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactOperationDaoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SchemaMetaDaoAdapter extends TypeAdapter<SchemaMetaDao> {
  @override
  final int typeId = 8;

  @override
  SchemaMetaDao read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SchemaMetaDao(
      schemaVersion: fields[0] as int,
      initializedAt: fields[1] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, SchemaMetaDao obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.schemaVersion)
      ..writeByte(1)
      ..write(obj.initializedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SchemaMetaDaoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class BuiltinBundleDaoAdapter extends TypeAdapter<BuiltinBundleDao> {
  @override
  final int typeId = 9;

  @override
  BuiltinBundleDao read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BuiltinBundleDao(
      bundleFamily: fields[0] as String,
      activeBundleId: fields[1] as String,
      itemKeys: (fields[2] as List).cast<String>(),
      updatedAt: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, BuiltinBundleDao obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.bundleFamily)
      ..writeByte(1)
      ..write(obj.activeBundleId)
      ..writeByte(2)
      ..write(obj.itemKeys)
      ..writeByte(3)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuiltinBundleDaoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
