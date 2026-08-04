import 'package:json_annotation/json_annotation.dart';

part 'dto.g.dart';

@JsonSerializable(explicitToJson: true)
class ResolveResult {
  final ResolvedTool tool;
  final String version;
  final String versionDigest;
  final ResolvedArtifact artifact;

  ResolveResult({
    required this.tool,
    required this.version,
    required this.versionDigest,
    required this.artifact,
  });

  factory ResolveResult.fromJson(Map<String, dynamic> json) =>
      _$ResolveResultFromJson(json);

  Map<String, dynamic> toJson() => _$ResolveResultToJson(this);
}

@JsonSerializable()
class ResolvedTool {
  final String namespace;
  final String name;

  ResolvedTool({required this.namespace, required this.name});

  factory ResolvedTool.fromJson(Map<String, dynamic> json) =>
      _$ResolvedToolFromJson(json);

  Map<String, dynamic> toJson() => _$ResolvedToolToJson(this);
}

@JsonSerializable()
class ResolvedArtifact {
  final String id;
  final String os;
  final String arch;
  final String abi;
  final String fileName;
  final String mediaType;
  final int size;
  final String digest;
  final String downloadUrl;
  final DateTime downloadUrlExpiresAt;

  ResolvedArtifact({
    required this.id,
    required this.os,
    required this.arch,
    required this.abi,
    required this.fileName,
    required this.mediaType,
    required this.size,
    required this.digest,
    required this.downloadUrl,
    required this.downloadUrlExpiresAt,
  });

  factory ResolvedArtifact.fromJson(Map<String, dynamic> json) =>
      _$ResolvedArtifactFromJson(json);

  Map<String, dynamic> toJson() => _$ResolvedArtifactToJson(this);
}

@JsonSerializable(createToJson: false)
class HubErrorEnvelope {
  final HubErrorBody error;

  HubErrorEnvelope({required this.error});

  factory HubErrorEnvelope.fromJson(Map<String, dynamic> json) =>
      _$HubErrorEnvelopeFromJson(json);
}

@JsonSerializable(createToJson: false)
class HubErrorBody {
  final String code;
  final String message;
  final String requestId;
  final Map<String, dynamic>? details;

  HubErrorBody({
    required this.code,
    required this.message,
    required this.requestId,
    this.details,
  });

  factory HubErrorBody.fromJson(Map<String, dynamic> json) =>
      _$HubErrorBodyFromJson(json);
}
