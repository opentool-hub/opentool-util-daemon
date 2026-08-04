// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ResolveResult _$ResolveResultFromJson(Map<String, dynamic> json) =>
    ResolveResult(
      tool: ResolvedTool.fromJson(json['tool'] as Map<String, dynamic>),
      version: json['version'] as String,
      versionDigest: json['versionDigest'] as String,
      artifact: ResolvedArtifact.fromJson(
        json['artifact'] as Map<String, dynamic>,
      ),
    );

Map<String, dynamic> _$ResolveResultToJson(ResolveResult instance) =>
    <String, dynamic>{
      'tool': instance.tool.toJson(),
      'version': instance.version,
      'versionDigest': instance.versionDigest,
      'artifact': instance.artifact.toJson(),
    };

ResolvedTool _$ResolvedToolFromJson(Map<String, dynamic> json) => ResolvedTool(
  namespace: json['namespace'] as String,
  name: json['name'] as String,
);

Map<String, dynamic> _$ResolvedToolToJson(ResolvedTool instance) =>
    <String, dynamic>{'namespace': instance.namespace, 'name': instance.name};

ResolvedArtifact _$ResolvedArtifactFromJson(Map<String, dynamic> json) =>
    ResolvedArtifact(
      id: json['id'] as String,
      os: json['os'] as String,
      arch: json['arch'] as String,
      abi: json['abi'] as String,
      fileName: json['fileName'] as String,
      mediaType: json['mediaType'] as String,
      size: (json['size'] as num).toInt(),
      digest: json['digest'] as String,
      downloadUrl: json['downloadUrl'] as String,
      downloadUrlExpiresAt: DateTime.parse(
        json['downloadUrlExpiresAt'] as String,
      ),
    );

Map<String, dynamic> _$ResolvedArtifactToJson(ResolvedArtifact instance) =>
    <String, dynamic>{
      'id': instance.id,
      'os': instance.os,
      'arch': instance.arch,
      'abi': instance.abi,
      'fileName': instance.fileName,
      'mediaType': instance.mediaType,
      'size': instance.size,
      'digest': instance.digest,
      'downloadUrl': instance.downloadUrl,
      'downloadUrlExpiresAt': instance.downloadUrlExpiresAt.toIso8601String(),
    };

HubErrorEnvelope _$HubErrorEnvelopeFromJson(Map<String, dynamic> json) =>
    HubErrorEnvelope(
      error: HubErrorBody.fromJson(json['error'] as Map<String, dynamic>),
    );

HubErrorBody _$HubErrorBodyFromJson(Map<String, dynamic> json) => HubErrorBody(
  code: json['code'] as String,
  message: json['message'] as String,
  requestId: json['requestId'] as String,
  details: json['details'] as Map<String, dynamic>?,
);
