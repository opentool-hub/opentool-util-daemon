import 'dart:convert';
import 'dart:io';

import 'package:unique_id_dart/unique_id_dart.dart';

import '../constants.dart';
import '../storage/artifact_storage.dart';
import '../storage/dao.dart';
import '../storage/storage.dart';
import '../utils/zip_util.dart';
import 'artifact_registry_service.dart';
import 'config.dart';
import 'exception.dart';

class BuiltinItemInput {
  final String key;
  final String path;
  final String expectedDigest;
  final int expectedSize;

  const BuiltinItemInput({
    required this.key,
    required this.path,
    required this.expectedDigest,
    required this.expectedSize,
  });
}

class BuiltinReconcileResult {
  final String bundleFamily;
  final String bundleId;
  final List<String> created;
  final List<String> reused;
  final List<String> retired;
  final List<Map<String, dynamic>> servers;

  const BuiltinReconcileResult({
    required this.bundleFamily,
    required this.bundleId,
    required this.created,
    required this.reused,
    required this.retired,
    required this.servers,
  });

  Map<String, dynamic> toJson() => {
    'bundleFamily': bundleFamily,
    'bundleId': bundleId,
    'created': created,
    'reused': reused,
    'retired': retired,
    'failed': const <Object>[],
    'servers': servers,
  };
}

class BuiltinReconcileService {
  final ArtifactRegistryService registry;
  final ArtifactStorage content;
  final Storage<ServerDao> servers;
  final Storage<BuiltinBundleDao> bundles;
  Future<void> _tail = Future<void>.value();

  BuiltinReconcileService({
    required this.registry,
    required this.content,
    required this.servers,
    required this.bundles,
  });

  Future<BuiltinReconcileResult> reconcile({
    required String bundleFamily,
    required String bundleId,
    required List<BuiltinItemInput> items,
  }) {
    final previous = _tail;
    late Future<BuiltinReconcileResult> task;
    task = previous
        .catchError((_) {})
        .then(
          (_) => _reconcileLocked(
            bundleFamily: bundleFamily,
            bundleId: bundleId,
            items: items,
          ),
        );
    _tail = task.then<void>((_) {}, onError: (_, __) {});
    return task;
  }

  Future<BuiltinReconcileResult> _reconcileLocked({
    required String bundleFamily,
    required String bundleId,
    required List<BuiltinItemInput> items,
  }) async {
    if (bundleFamily.trim().isEmpty || bundleId.trim().isEmpty) {
      throw const ArtifactOperationException(
        code: 'INVALID_REQUEST',
        message: 'bundleFamily and bundleId are required',
        retryable: false,
      );
    }
    final keys = <String>{};
    for (final item in items) {
      if (item.key.trim().isEmpty || !keys.add(item.key)) {
        throw const ArtifactOperationException(
          code: 'INVALID_REQUEST',
          message: 'Builtin item keys must be non-empty and unique',
          retryable: false,
        );
      }
    }
    final active = await _reuseActiveBundle(
      bundleFamily: bundleFamily,
      bundleId: bundleId,
      items: items,
      keys: keys,
    );
    if (active != null) return active;

    final validated = <String, _ValidatedBuiltin>{};
    try {
      for (final item in items) {
        String? tempPath;
        try {
          final write = await content.copyToPart(item.path);
          tempPath = write.tempPath;
          if (write.digest != item.expectedDigest) {
            throw const ArtifactOperationException(
              code: 'ARTIFACT_DIGEST_MISMATCH',
              message:
                  'Builtin artifact digest does not match expected metadata',
              retryable: false,
            );
          }
          if (write.size != item.expectedSize) {
            throw const ArtifactOperationException(
              code: 'ARTIFACT_SIZE_MISMATCH',
              message: 'Builtin artifact size does not match expected metadata',
              retryable: false,
            );
          }
          final inspection = await ZipUtil.inspect(write.tempPath);
          final config = OpentoolfileConfig.fromJson(inspection.manifest);
          validated[item.key] = _ValidatedBuiltin(item, write, config);
        } catch (_) {
          await content.deleteIfExists(tempPath);
          rethrow;
        }
      }
    } catch (_) {
      for (final item in validated.values) {
        await content.deleteIfExists(item.write.tempPath);
      }
      rethrow;
    }

    final snapshot = (await servers.list())
        .where(
          (server) =>
              server.sourceKind == 'builtin' &&
              server.builtinBundleFamily == bundleFamily,
        )
        .toList();
    final previousBundle = await bundles.get(bundleFamily);
    final createdServerIds = <String>[];
    final operationNow = DateTime.now().toUtc();
    final operation = ArtifactOperationDao(
      id: uniqueId(shorter: false),
      type: 'builtinReconcile',
      stage: 'created',
      sourceKind: 'builtin',
      sourceKey: bundleFamily,
      payloadJson: jsonEncode({
        'bundleFamily': bundleFamily,
        'desiredBundleId': bundleId,
        'familyServers': snapshot.map(_serverToJson).toList(),
        'createdServerIds': createdServerIds,
        'previousBundle': previousBundle == null
            ? null
            : _bundleToJson(previousBundle),
      }),
      createdAt: operationNow,
      updatedAt: operationNow,
    );
    await registry.operations.add(operation);
    final created = <String>[];
    final reused = <String>[];
    final retired = <String>[];
    try {
      for (final entry
          in validated.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))) {
        final item = entry.value;
        final sourceKey = '$bundleFamily|${entry.key}';
        final existing = await registry.findBySource('builtin', sourceKey);
        final createdServerId = existing == null ? uniqueId() : null;
        if (createdServerId != null) {
          createdServerIds.add(createdServerId);
          await _updateOperationPayload(
            operation,
            bundleFamily: bundleFamily,
            bundleId: bundleId,
            snapshot: snapshot,
            createdServerIds: createdServerIds,
            previousBundle: previousBundle,
          );
        }
        final result = await registry.registerPreparedArtifact(
          item.write,
          ServerReferenceInput.builtin(
            bundleFamily: bundleFamily,
            bundleId: bundleId,
            key: entry.key,
            namespace: LOCAL_NAMESPACE,
            name: item.config.name,
            version: item.config.tag ?? NULL_TAG,
            preferredServerId: createdServerId,
          ),
          const RegistrationPolicy(
            protected: true,
            managedBy: 'agentos-embedded',
            allowReferenceUpdate: true,
          ),
          expectedMetadata: ArtifactExpectedMetadata(
            digest: item.input.expectedDigest,
            size: item.input.expectedSize,
            name: item.config.name,
            version: item.config.tag ?? NULL_TAG,
          ),
          notify: false,
        );
        if (existing == null) {
          created.add(entry.key);
        } else {
          reused.add(entry.key);
        }
        if (result.state != 'available') {
          result.state = 'available';
          await servers.update(result);
        }
      }

      for (final server in (await servers.list()).where(
        (server) =>
            server.sourceKind == 'builtin' &&
            server.builtinBundleFamily == bundleFamily &&
            !keys.contains(server.builtinKey),
      )) {
        server.state = 'retired';
        server.builtinBundleId = bundleId;
        await servers.update(server);
        if (server.builtinKey != null) retired.add(server.builtinKey!);
      }
      operation.stage = 'referenceWritten';
      operation.updatedAt = DateTime.now().toUtc();
      await registry.operations.update(operation);
      await bundles.update(
        BuiltinBundleDao(
          bundleFamily: bundleFamily,
          activeBundleId: bundleId,
          itemKeys: keys.toList()..sort(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      operation.stage = 'committed';
      operation.updatedAt = DateTime.now().toUtc();
      await registry.operations.update(operation);
      await registry.operations.remove(operation.id);
      try {
        await registry.notifyServersChanged();
      } catch (_) {
        // Desired state is already durable; notification is best-effort.
      }
    } catch (_) {
      for (final serverId in createdServerIds) await servers.remove(serverId);
      for (final server in snapshot) await servers.update(server);
      if (previousBundle == null) {
        await bundles.remove(bundleFamily);
      } else {
        await bundles.update(previousBundle);
      }
      await registry.operations.remove(operation.id);
      await registry.garbageCollect();
      rethrow;
    } finally {
      for (final item in validated.values) {
        await content.deleteIfExists(item.write.tempPath);
      }
    }

    return _result(
      bundleFamily: bundleFamily,
      bundleId: bundleId,
      created: created,
      reused: reused,
      retired: retired,
    );
  }

  Future<BuiltinReconcileResult?> _reuseActiveBundle({
    required String bundleFamily,
    required String bundleId,
    required List<BuiltinItemInput> items,
    required Set<String> keys,
  }) async {
    final bundle = await bundles.get(bundleFamily);
    if (bundle?.activeBundleId != bundleId) return null;
    final storedKeys = [...bundle!.itemKeys]..sort();
    final desiredKeys = keys.toList()..sort();
    if (!_sameStrings(storedKeys, desiredKeys)) return null;

    final familyServers = (await servers.list())
        .where(
          (server) =>
              server.sourceKind == 'builtin' &&
              server.builtinBundleFamily == bundleFamily,
        )
        .toList();
    for (final item in items) {
      ServerDao? matched;
      for (final server in familyServers) {
        if (server.builtinKey == item.key &&
            server.sourceKey == '$bundleFamily|${item.key}') {
          matched = server;
          break;
        }
      }
      if (matched == null ||
          matched.builtinBundleId != bundleId ||
          matched.artifactDigest != item.expectedDigest ||
          matched.state != 'available') {
        return null;
      }
      final artifact = await registry.artifacts.get(item.expectedDigest);
      if (artifact == null ||
          artifact.digest != item.expectedDigest ||
          artifact.size != item.expectedSize) {
        return null;
      }
      final stat = await File(artifact.filePath).stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size != item.expectedSize) {
        return null;
      }
    }
    return _result(
      bundleFamily: bundleFamily,
      bundleId: bundleId,
      created: const [],
      reused: desiredKeys,
      retired: const [],
      familyServers: familyServers,
    );
  }

  Future<BuiltinReconcileResult> _result({
    required String bundleFamily,
    required String bundleId,
    required List<String> created,
    required List<String> reused,
    required List<String> retired,
    List<ServerDao>? familyServers,
  }) async {
    final current =
        familyServers ??
        (await servers.list())
            .where(
              (server) =>
                  server.sourceKind == 'builtin' &&
                  server.builtinBundleFamily == bundleFamily,
            )
            .toList();
    return BuiltinReconcileResult(
      bundleFamily: bundleFamily,
      bundleId: bundleId,
      created: created,
      reused: reused,
      retired: retired,
      servers: current
          .map(
            (server) => {
              'id': server.id,
              'alias': server.alias,
              'namespace': server.namespace,
              'name': server.name,
              'version': server.version,
              'artifactDigest': server.artifactDigest,
              'state': server.state,
              'source': {
                'kind': server.sourceKind,
                'builtinKey': server.builtinKey,
                'bundleId': server.builtinBundleId,
              },
            },
          )
          .toList(),
    );
  }

  static bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  Future<void> recover() async {
    for (final operation in (await registry.operations.list()).where(
      (item) => item.type == 'builtinReconcile',
    )) {
      final decoded = operation.payloadJson == null
          ? null
          : jsonDecode(operation.payloadJson!);
      if (decoded is! Map<String, dynamic>) {
        await registry.operations.remove(operation.id);
        continue;
      }
      final family = decoded['bundleFamily'] as String?;
      final desiredBundleId = decoded['desiredBundleId'] as String?;
      if (family == null || desiredBundleId == null) {
        await registry.operations.remove(operation.id);
        continue;
      }
      final active = await bundles.get(family);
      if (active?.activeBundleId == desiredBundleId) {
        await registry.operations.remove(operation.id);
        continue;
      }
      final rawServers = decoded['familyServers'];
      if (rawServers is List) {
        final snapshot = rawServers
            .map(
              (value) =>
                  _serverFromJson(Map<String, dynamic>.from(value as Map)),
            )
            .toList();
        final rawCreatedIds = decoded['createdServerIds'];
        if (rawCreatedIds is List) {
          for (final serverId in rawCreatedIds.whereType<String>()) {
            await servers.remove(serverId);
          }
        }
        for (final server in snapshot) await servers.update(server);
      }
      final rawBundle = decoded['previousBundle'];
      if (rawBundle is Map) {
        await bundles.update(
          _bundleFromJson(Map<String, dynamic>.from(rawBundle)),
        );
      } else {
        await bundles.remove(family);
      }
      await registry.operations.remove(operation.id);
    }
    await registry.garbageCollect();
  }

  Future<void> _updateOperationPayload(
    ArtifactOperationDao operation, {
    required String bundleFamily,
    required String bundleId,
    required List<ServerDao> snapshot,
    required List<String> createdServerIds,
    required BuiltinBundleDao? previousBundle,
  }) async {
    operation.payloadJson = jsonEncode({
      'bundleFamily': bundleFamily,
      'desiredBundleId': bundleId,
      'familyServers': snapshot.map(_serverToJson).toList(),
      'createdServerIds': createdServerIds,
      'previousBundle': previousBundle == null
          ? null
          : _bundleToJson(previousBundle),
    });
    operation.updatedAt = DateTime.now().toUtc();
    await registry.operations.update(operation);
  }

  static Map<String, dynamic> _serverToJson(ServerDao server) => {
    'id': server.id,
    'alias': server.alias,
    'namespace': server.namespace,
    'name': server.name,
    'version': server.version,
    'artifactDigest': server.artifactDigest,
    'sourceKind': server.sourceKind,
    'sourceKey': server.sourceKey,
    'registry': server.registry,
    'versionDigest': server.versionDigest,
    'hubArtifactId': server.hubArtifactId,
    'builtinBundleFamily': server.builtinBundleFamily,
    'builtinBundleId': server.builtinBundleId,
    'builtinKey': server.builtinKey,
    'protected': server.protected,
    'managedBy': server.managedBy,
    'state': server.state,
    'createdAt': server.createdAt.toIso8601String(),
  };

  static ServerDao _serverFromJson(Map<String, dynamic> json) => ServerDao(
    id: json['id'] as String,
    alias: json['alias'] as String,
    namespace: json['namespace'] as String,
    name: json['name'] as String,
    version: json['version'] as String,
    artifactDigest: json['artifactDigest'] as String,
    sourceKind: json['sourceKind'] as String,
    sourceKey: json['sourceKey'] as String,
    registry: json['registry'] as String?,
    versionDigest: json['versionDigest'] as String?,
    hubArtifactId: json['hubArtifactId'] as String?,
    builtinBundleFamily: json['builtinBundleFamily'] as String?,
    builtinBundleId: json['builtinBundleId'] as String?,
    builtinKey: json['builtinKey'] as String?,
    protected: json['protected'] as bool,
    managedBy: json['managedBy'] as String,
    state: json['state'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  static Map<String, dynamic> _bundleToJson(BuiltinBundleDao bundle) => {
    'bundleFamily': bundle.bundleFamily,
    'activeBundleId': bundle.activeBundleId,
    'itemKeys': bundle.itemKeys,
    'updatedAt': bundle.updatedAt.toIso8601String(),
  };

  static BuiltinBundleDao _bundleFromJson(Map<String, dynamic> json) =>
      BuiltinBundleDao(
        bundleFamily: json['bundleFamily'] as String,
        activeBundleId: json['activeBundleId'] as String,
        itemKeys: List<String>.from(json['itemKeys'] as List),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class _ValidatedBuiltin {
  final BuiltinItemInput input;
  final ArtifactWriteResult write;
  final OpentoolfileConfig config;
  const _ValidatedBuiltin(this.input, this.write, this.config);
}

class HostManagementAuthenticator {
  final List<int>? _token;

  HostManagementAuthenticator._(this._token);

  factory HostManagementAuthenticator.fromToken(String token) {
    final bytes = utf8.encode(token.trim());
    return HostManagementAuthenticator._(bytes.length < 32 ? null : bytes);
  }

  static Future<HostManagementAuthenticator> fromEnvironment() async {
    final path = Platform.environment['OPENTOOL_HOST_TOKEN_FILE'];
    if (path == null || path.isEmpty)
      return HostManagementAuthenticator._(null);
    final file = File(path);
    if (!await file.exists()) return HostManagementAuthenticator._(null);
    return HostManagementAuthenticator.fromToken(await file.readAsString());
  }

  bool authorize(String? provided) {
    final expected = _token;
    final actual = provided == null ? const <int>[] : utf8.encode(provided);
    if (expected == null) return false;
    var difference = expected.length ^ actual.length;
    final length = expected.length > actual.length
        ? expected.length
        : actual.length;
    for (var index = 0; index < length; index++) {
      final left = index < expected.length ? expected[index] : 0;
      final right = index < actual.length ? actual[index] : 0;
      difference |= left ^ right;
    }
    return difference == 0;
  }
}
