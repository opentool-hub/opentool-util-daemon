import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:unique_id_dart/unique_id_dart.dart';

import '../constants.dart';
import '../storage/artifact_storage.dart';
import '../storage/dao.dart';
import '../storage/storage.dart';
import '../utils/zip_util.dart';
import 'config.dart';
import 'exception.dart';
import 'model.dart';

class ArtifactExpectedMetadata {
  final String? digest;
  final int? size;
  final String? name;
  final String? version;
  final ServerPlatform? platform;

  const ArtifactExpectedMetadata({
    this.digest,
    this.size,
    this.name,
    this.version,
    this.platform,
  });
}

class ServerReferenceInput {
  final String sourceKind;
  final String sourceKey;
  final String namespace;
  final String name;
  final String version;
  final String? alias;
  final String? registry;
  final int? versionRevision;
  final String? versionDigest;
  final String? hubArtifactId;
  final String? builtinBundleFamily;
  final String? builtinBundleId;
  final String? builtinKey;
  final String? preferredServerId;

  const ServerReferenceInput({
    required this.sourceKind,
    required this.sourceKey,
    required this.namespace,
    required this.name,
    required this.version,
    this.alias,
    this.registry,
    this.versionRevision,
    this.versionDigest,
    this.hubArtifactId,
    this.builtinBundleFamily,
    this.builtinBundleId,
    this.builtinKey,
    this.preferredServerId,
  });

  factory ServerReferenceInput.hub({
    required String registry,
    required String namespace,
    required String name,
    required String version,
    required int versionRevision,
    required String versionDigest,
    required String hubArtifactId,
  }) => ServerReferenceInput(
    sourceKind: 'hub',
    sourceKey: '$registry|$namespace|$name|$version',
    namespace: namespace,
    name: name,
    version: version,
    alias: name,
    registry: registry,
    versionRevision: versionRevision,
    versionDigest: versionDigest,
    hubArtifactId: hubArtifactId,
  );

  factory ServerReferenceInput.local({
    required String kind,
    required String namespace,
    required String name,
    required String version,
    String? projectKey,
  }) {
    final key = [
      namespace,
      name,
      version,
      if (projectKey != null) projectKey,
    ].join('|');
    return ServerReferenceInput(
      sourceKind: kind,
      sourceKey: key,
      namespace: namespace,
      name: name,
      version: version,
      alias: name,
    );
  }

  factory ServerReferenceInput.builtin({
    required String bundleFamily,
    required String bundleId,
    required String key,
    required String namespace,
    required String name,
    required String version,
    String? preferredServerId,
    String? alias,
  }) => ServerReferenceInput(
    sourceKind: 'builtin',
    sourceKey: '$bundleFamily|$key',
    namespace: namespace,
    name: name,
    version: version,
    alias: alias ?? name,
    builtinBundleFamily: bundleFamily,
    builtinBundleId: bundleId,
    builtinKey: key,
    preferredServerId: preferredServerId,
  );
}

class RegistrationPolicy {
  final bool protected;
  final String managedBy;
  final bool allowReferenceUpdate;

  const RegistrationPolicy({
    this.protected = false,
    this.managedBy = 'user',
    this.allowReferenceUpdate = false,
  });
}

class ServerDeleteResult {
  final String serverId;
  final bool artifactRemoved;

  const ServerDeleteResult({
    required this.serverId,
    required this.artifactRemoved,
  });
}

class ArtifactRegistryService {
  final ArtifactStorage content;
  final Storage<ArtifactDao> artifacts;
  final Storage<ServerDao> servers;
  final Storage<ArtifactOperationDao> operations;
  final Storage<ToolDao>? tools;
  final Future<void> Function()? onServersChanged;
  final Map<String, _AsyncLock> _sourceLocks = {};
  final Map<String, _AsyncLock> _digestLocks = {};

  ArtifactRegistryService({
    required this.content,
    required this.artifacts,
    required this.servers,
    required this.operations,
    this.tools,
    this.onServersChanged,
  });

  Future<ServerDao> registerArtifact(
    String sourcePath,
    ServerReferenceInput reference,
    RegistrationPolicy policy, {
    ArtifactExpectedMetadata? expectedMetadata,
    bool notify = true,
  }) async {
    _validateReference(reference, policy);
    late final ArtifactWriteResult write;
    try {
      write = await content.copyToPart(sourcePath);
    } on FileSystemException catch (error) {
      throw ArtifactOperationException(
        code: 'REGISTER_FAILED',
        message: error.message,
        retryable: true,
      );
    }
    return registerPreparedArtifact(
      write,
      reference,
      policy,
      expectedMetadata: expectedMetadata,
      notify: notify,
    );
  }

  /// Registers a part that has already been copied and digested by [content].
  /// Ownership of [write.tempPath] transfers to this method.
  Future<ServerDao> registerPreparedArtifact(
    ArtifactWriteResult write,
    ServerReferenceInput reference,
    RegistrationPolicy policy, {
    ArtifactExpectedMetadata? expectedMetadata,
    bool notify = true,
  }) async {
    try {
      _validateReference(reference, policy);
    } catch (_) {
      await content.deleteIfExists(write.tempPath);
      rethrow;
    }
    final now = DateTime.now().toUtc();
    final operation = ArtifactOperationDao(
      id: uniqueId(shorter: false),
      type: reference.sourceKind == 'builtin' ? 'builtin' : 'register',
      stage: 'created',
      sourceKind: reference.sourceKind,
      sourceKey: reference.sourceKey,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await operations.add(operation);
    } catch (_) {
      await content.deleteIfExists(write.tempPath);
      rethrow;
    }
    var durableState = false;
    try {
      operation.tempPath = write.tempPath;
      operation.digest = write.digest;
      await _updateOperation(operation, 'contentWritten');
      _validateExpected(write, expectedMetadata);
      final inspected = await _inspectAndValidate(
        write.tempPath,
        reference,
        expectedMetadata,
      );

      return await _sourceLock(reference).protect(() async {
        final completedWrite = write;
        final existing = await findBySource(
          reference.sourceKind,
          reference.sourceKey,
        );
        if (existing != null &&
            existing.artifactDigest == completedWrite.digest &&
            !policy.allowReferenceUpdate) {
          final artifact = await artifacts.get(existing.artifactDigest);
          if (artifact != null && await File(artifact.filePath).exists()) {
            await content.verify(
              artifact.filePath,
              artifact.digest,
              artifact.size,
            );
            await content.deleteIfExists(completedWrite.tempPath);
            await operations.remove(operation.id);
            return existing;
          }
        }
        if (existing != null &&
            existing.artifactDigest != completedWrite.digest &&
            !policy.allowReferenceUpdate) {
          throw const ArtifactOperationException(
            code: 'ARTIFACT_SOURCE_CONFLICT',
            message: 'The source identity already references different content',
            retryable: false,
          );
        }

        final result = await _digestLock(completedWrite.digest).protect(
          () async {
            final contentPath = await content.commitPart(completedWrite);
            durableState = true;
            final oldArtifact = await artifacts.get(completedWrite.digest);
            if (oldArtifact == null) {
              await artifacts.add(
                ArtifactDao(
                  digest: completedWrite.digest,
                  size: completedWrite.size,
                  mediaType: 'application/vnd.opentool.ots',
                  platformOs: inspected.config.os.toLowerCase(),
                  platformArch: inspected.config.cpuArch.toLowerCase(),
                  platformAbi: OpentoolfileConfigUtil.resolvedAbi(
                    inspected.config.os,
                    inspected.config.abi,
                  ),
                  filePath: contentPath,
                  manifestName: inspected.config.name,
                  manifestVersion: inspected.config.tag ?? NULL_TAG,
                  verifiedAt: DateTime.now().toUtc(),
                  createdAt: DateTime.now().toUtc(),
                ),
              );
            }
            await _updateOperation(operation, 'artifactWritten');

            final server = ServerDao(
              id: existing?.id ?? reference.preferredServerId ?? uniqueId(),
              alias: existing?.alias ?? reference.alias ?? reference.name,
              namespace: reference.namespace,
              name: reference.name,
              version: reference.version,
              artifactDigest: completedWrite.digest,
              sourceKind: reference.sourceKind,
              sourceKey: reference.sourceKey,
              registry: reference.registry,
              versionRevision: reference.versionRevision,
              versionDigest: reference.versionDigest,
              hubArtifactId: reference.hubArtifactId,
              builtinBundleFamily: reference.builtinBundleFamily,
              builtinBundleId: reference.builtinBundleId,
              builtinKey: reference.builtinKey,
              protected: policy.protected,
              managedBy: policy.managedBy,
              state: 'available',
              createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
            );
            operation.serverId = server.id;
            if (existing == null) {
              await servers.add(server);
            } else {
              await servers.update(server);
            }
            await _updateOperation(operation, 'referenceWritten');
            await _updateOperation(operation, 'committed');
            await operations.remove(operation.id);
            if (notify) {
              try {
                await onServersChanged?.call();
              } catch (_) {
                // Persistence is authoritative; observers will converge on list.
              }
            }
            return server;
          },
        );
        if (existing != null &&
            existing.artifactDigest != completedWrite.digest) {
          await _gcUnreferencedDigest(existing.artifactDigest);
        }
        return result;
      });
    } on ArtifactOperationException {
      if (!durableState) {
        await content.deleteIfExists(write.tempPath);
        await operations.remove(operation.id);
      }
      rethrow;
    } on FormatException catch (error) {
      await content.deleteIfExists(write.tempPath);
      if (!durableState) await operations.remove(operation.id);
      throw ArtifactOperationException(
        code: 'ARTIFACT_INVALID',
        message: error.message,
        retryable: false,
      );
    } on FileSystemException catch (error) {
      await content.deleteIfExists(write.tempPath);
      if (!durableState) await operations.remove(operation.id);
      throw ArtifactOperationException(
        code: 'REGISTER_FAILED',
        message: error.message,
        retryable: true,
      );
    }
  }

  Future<ServerDao?> findBySource(String kind, String key) async {
    for (final server in await servers.list()) {
      if (server.sourceKind == kind && server.sourceKey == key) return server;
    }
    return null;
  }

  Future<ServerDeleteResult> removeServer(String serverId) async {
    final initial = await servers.get(serverId);
    if (initial == null) throw ServerNotFoundException(serverId);
    final reference = ServerReferenceInput(
      sourceKind: initial.sourceKind,
      sourceKey: initial.sourceKey,
      namespace: initial.namespace,
      name: initial.name,
      version: initial.version,
    );
    return _sourceLock(reference).protect(() async {
      final server = await servers.get(serverId);
      if (server == null) throw ServerNotFoundException(serverId);
      if (server.protected) {
        throw const ServerPolicyException(
          code: 'SERVER_PROTECTED',
          message: 'Protected servers can only be changed by their manager',
        );
      }
      if (tools != null &&
          (await tools!.list()).any((tool) => tool.serverId == serverId)) {
        throw const ServerPolicyException(
          code: 'SERVER_IN_USE',
          message: 'The server is referenced by a Tool',
        );
      }

      final now = DateTime.now().toUtc();
      final operation = ArtifactOperationDao(
        id: uniqueId(shorter: false),
        type: 'remove',
        stage: 'created',
        digest: server.artifactDigest,
        serverId: server.id,
        sourceKind: server.sourceKind,
        sourceKey: server.sourceKey,
        payloadJson: jsonEncode({'server': _serverJson(server)}),
        createdAt: now,
        updatedAt: now,
      );
      await operations.add(operation);
      await servers.remove(server.id);
      await _updateOperation(operation, 'referenceRemoved');
      final removed = await _digestLock(server.artifactDigest).protect(
        () async {
          if (await _artifactIsReferenced(
            server.artifactDigest,
            operation.id,
          )) {
            return false;
          }
          final trashPath = await content.moveToTrash(
            server.artifactDigest,
            operation.id,
          );
          operation.tempPath = trashPath;
          await _updateOperation(operation, 'contentTrashed');
          await artifacts.remove(server.artifactDigest);
          await _updateOperation(operation, 'artifactRemoved');
          return true;
        },
      );
      await _updateOperation(operation, 'committed');
      if (removed) await content.deleteIfExists(operation.tempPath);
      await operations.remove(operation.id);
      await onServersChanged?.call();
      return ServerDeleteResult(serverId: serverId, artifactRemoved: removed);
    });
  }

  Future<void> recover() async {
    await content.cleanupParts();
    for (final operation in await operations.list()) {
      if (operation.type == 'materialize' ||
          operation.type == 'builtinReconcile') {
        continue;
      }
      if (operation.type == 'remove' || operation.type == 'gc') {
        await _recoverRemove(operation);
      } else {
        await _recoverRegister(operation);
      }
    }
    await _markBrokenServers();
    await _removeOrphanArtifacts();
    await _removeOrphanContent();
  }

  Future<void> garbageCollect() async {
    for (final artifact in await artifacts.list()) {
      await _gcUnreferencedDigest(artifact.digest);
    }
  }

  Future<void> notifyServersChanged() async => onServersChanged?.call();

  Future<void> _recoverRegister(ArtifactOperationDao operation) async {
    final digest = operation.digest;
    final serverId = operation.serverId;
    final referenceExists =
        serverId != null && await servers.get(serverId) != null;
    if (referenceExists) {
      await content.deleteIfExists(operation.tempPath);
      await operations.remove(operation.id);
      return;
    }
    await content.deleteIfExists(operation.tempPath);
    if (digest != null && !await _artifactIsReferenced(digest, operation.id)) {
      final artifact = await artifacts.remove(digest);
      await content.deleteIfExists(
        artifact?.filePath ?? content.pathForDigest(digest),
      );
    }
    await operations.remove(operation.id);
  }

  Future<void> _recoverRemove(ArtifactOperationDao operation) async {
    final digest = operation.digest;
    if (digest == null) {
      await operations.remove(operation.id);
      return;
    }
    if (await _artifactIsReferenced(digest, operation.id)) {
      final trash = operation.tempPath;
      final target = content.pathForDigest(digest);
      if (trash != null &&
          await File(trash).exists() &&
          !await File(target).exists()) {
        await File(target).parent.create(recursive: true);
        await File(trash).rename(target);
      }
    } else {
      await artifacts.remove(digest);
      await content.deleteIfExists(operation.tempPath);
      await content.deleteIfExists(content.pathForDigest(digest));
    }
    await operations.remove(operation.id);
  }

  Future<void> _markBrokenServers() async {
    for (final server in await servers.list()) {
      final artifact = await artifacts.get(server.artifactDigest);
      final intact = artifact != null && await File(artifact.filePath).exists();
      final nextState = intact
          ? (server.state == 'broken' ? 'available' : server.state)
          : 'broken';
      if (nextState != server.state) {
        server.state = nextState;
        await servers.update(server);
      }
    }
  }

  Future<void> _removeOrphanArtifacts() async {
    for (final artifact in await artifacts.list()) {
      if (!await _artifactIsReferenced(artifact.digest, null)) {
        await artifacts.remove(artifact.digest);
        await content.deleteIfExists(artifact.filePath);
      }
    }
  }

  Future<void> _removeOrphanContent() async {
    final root = Directory(p.join(content.contentRoot, 'sha256'));
    if (!await root.exists()) return;
    final tracked = (await artifacts.list())
        .map((a) => p.normalize(a.filePath))
        .toSet();
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && !tracked.contains(p.normalize(entity.path))) {
        await entity.delete();
      }
    }
    final trash = Directory(content.trashRoot);
    if (await trash.exists()) {
      await for (final entity in trash.list(followLinks: false)) {
        if (entity is File) await entity.delete();
      }
    }
  }

  Future<void> _gcUnreferencedDigest(String digest) =>
      _digestLock(digest).protect(() async {
        if (await _artifactIsReferenced(digest, null)) return;
        final artifact = await artifacts.remove(digest);
        await content.deleteIfExists(
          artifact?.filePath ?? content.pathForDigest(digest),
        );
      });

  Future<bool> _artifactIsReferenced(
    String digest,
    String? ignoreOperation,
  ) async {
    if ((await servers.list()).any(
      (server) => server.artifactDigest == digest,
    )) {
      return true;
    }
    return (await operations.list()).any(
      (operation) =>
          operation.id != ignoreOperation && operation.digest == digest,
    );
  }

  Future<_ValidatedArtifact> _inspectAndValidate(
    String path,
    ServerReferenceInput reference,
    ArtifactExpectedMetadata? expected,
  ) async {
    final inspection = await ZipUtil.inspect(path);
    final config = OpentoolfileConfig.fromJson(inspection.manifest);
    final version = config.tag ?? NULL_TAG;
    if (expected?.name != null &&
        _normalizeName(config.name) != _normalizeName(expected!.name!)) {
      throw const FormatException(
        'Artifact name does not match expected metadata',
      );
    }
    if (expected?.version != null && version != expected!.version) {
      throw const FormatException(
        'Artifact version does not match expected metadata',
      );
    }
    if (_normalizeName(config.name) != _normalizeName(reference.name) ||
        version != reference.version) {
      throw const FormatException(
        'Artifact manifest does not match its Server reference',
      );
    }
    final manifestOs = config.os.trim().toLowerCase();
    final manifestArch = config.cpuArch.trim().toLowerCase();
    final manifestAbi = OpentoolfileConfigUtil.resolvedAbi(
      manifestOs,
      config.abi,
    );
    if (!OpentoolfileConfigUtil.isSupportedAbi(manifestOs, manifestAbi)) {
      throw const ArtifactOperationException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'Artifact ABI is invalid for its operating system',
        retryable: false,
      );
    }
    if (expected?.platform != null &&
        (manifestOs != expected!.platform!.os ||
            manifestArch != expected.platform!.arch ||
            manifestAbi != expected.platform!.abi)) {
      throw const ArtifactOperationException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'Artifact platform does not match the requested platform',
        retryable: false,
      );
    }
    final resolved = OpentoolfileConfigUtil.resolve(config);
    final workdir = resolved.run.workdir.trim().isEmpty
        ? '.'
        : resolved.run.workdir.trim();
    final entrypoint = resolved.run.entrypoint.trim();
    if (workdir.contains(r'\') ||
        entrypoint.contains(r'\') ||
        p.posix.isAbsolute(workdir) ||
        p.posix.isAbsolute(entrypoint)) {
      throw const FormatException(
        'Tool entrypoint is not a safe relative path',
      );
    }
    final executable = p.posix.normalize(p.posix.join(workdir, entrypoint));
    if (executable == '.' ||
        executable == '..' ||
        executable.startsWith('../')) {
      throw const FormatException('Tool entrypoint escapes the artifact');
    }
    final candidates = <String>[executable];
    if (config.os.toLowerCase() == 'windows' &&
        p.posix.extension(executable).isEmpty) {
      candidates.addAll([
        '$executable.exe',
        '$executable.cmd',
        '$executable.bat',
      ]);
    }
    if (!candidates.any(inspection.files.contains) &&
        !_isBareEntrypoint(entrypoint)) {
      throw const FormatException(
        'Tool entrypoint is missing from the artifact',
      );
    }
    return _ValidatedArtifact(config);
  }

  void _validateExpected(
    ArtifactWriteResult write,
    ArtifactExpectedMetadata? expected,
  ) {
    if (expected?.size != null && expected!.size != write.size) {
      throw const ArtifactOperationException(
        code: 'ARTIFACT_SIZE_MISMATCH',
        message: 'Artifact size does not match expected metadata',
        retryable: false,
      );
    }
    if (expected?.digest != null && expected!.digest != write.digest) {
      throw const ArtifactOperationException(
        code: 'ARTIFACT_DIGEST_MISMATCH',
        message: 'Artifact digest does not match expected metadata',
        retryable: false,
      );
    }
  }

  void _validateReference(
    ServerReferenceInput reference,
    RegistrationPolicy policy,
  ) {
    if (!const {
          'hub',
          'builtin',
          'import',
          'build',
        }.contains(reference.sourceKind) ||
        reference.sourceKey.trim().isEmpty ||
        reference.namespace.trim().isEmpty ||
        reference.name.trim().isEmpty ||
        reference.version.trim().isEmpty ||
        (reference.sourceKind == 'builtin' && !policy.protected)) {
      throw const ArtifactOperationException(
        code: 'INVALID_REQUEST',
        message: 'Artifact Server reference is invalid',
        retryable: false,
      );
    }
  }

  Future<void> _updateOperation(
    ArtifactOperationDao operation,
    String stage,
  ) async {
    operation.stage = stage;
    operation.updatedAt = DateTime.now().toUtc();
    await operations.update(operation);
  }

  _AsyncLock _sourceLock(ServerReferenceInput reference) =>
      _sourceLocks.putIfAbsent(
        '${reference.sourceKind}|${reference.sourceKey}',
        _AsyncLock.new,
      );
  _AsyncLock _digestLock(String digest) =>
      _digestLocks.putIfAbsent(digest, _AsyncLock.new);

  String _normalizeName(String value) =>
      value.trim().toLowerCase().replaceFirst(RegExp(r'^opentool-server-'), '');

  Map<String, dynamic> _serverJson(ServerDao server) => {
    'id': server.id,
    'alias': server.alias,
    'namespace': server.namespace,
    'name': server.name,
    'version': server.version,
    'artifactDigest': server.artifactDigest,
    'sourceKind': server.sourceKind,
    'sourceKey': server.sourceKey,
  };
}

bool _isBareEntrypoint(String entrypoint) =>
    entrypoint.isNotEmpty &&
    entrypoint != '.' &&
    entrypoint != '..' &&
    !entrypoint.contains('/') &&
    !entrypoint.contains(r'\');

class _ValidatedArtifact {
  final OpentoolfileConfig config;
  const _ValidatedArtifact(this.config);
}

class _AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> protect<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous.catchError((_) {});
    try {
      return await action();
    } finally {
      done.complete();
    }
  }
}
