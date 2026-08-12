import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:opentool_daemon/src/service/artifact_registry_service.dart';
import 'package:opentool_daemon/src/service/builtin_reconcile_service.dart';
import 'package:opentool_daemon/src/service/exception.dart';
import 'package:opentool_daemon/src/service/model.dart';
import 'package:opentool_daemon/src/service/tool_materialization_service.dart';
import 'package:opentool_daemon/src/storage/artifact_storage.dart';
import 'package:opentool_daemon/src/storage/dao.dart';
import 'package:opentool_daemon/src/storage/storage.dart';
import 'package:opentool_daemon/src/utils/zip_util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ArtifactRegistryService', () {
    late Directory root;
    late _MemoryStorage<ArtifactDao> artifacts;
    late _MemoryStorage<ServerDao> servers;
    late _MemoryStorage<ArtifactOperationDao> operations;
    late _MemoryStorage<ToolDao> tools;
    late ArtifactRegistryService registry;
    late File artifact;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('artifact_registry_test_');
      artifacts = _MemoryStorage((value) => value.digest);
      servers = _MemoryStorage((value) => value.id);
      operations = _MemoryStorage((value) => value.id);
      tools = _MemoryStorage((value) => value.id);
      registry = ArtifactRegistryService(
        content: ArtifactStorage(root.path),
        artifacts: artifacts,
        servers: servers,
        operations: operations,
        tools: tools,
      );
      artifact = await _createArtifact(root, marker: 'one');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'deduplicates content while retaining independent Server refs',
      () async {
        final imported = await registry.registerArtifact(
          artifact.path,
          ServerReferenceInput.local(
            kind: 'import',
            namespace: 'local',
            name: 'demo',
            version: '1.0.0',
          ),
          const RegistrationPolicy(),
        );
        final digest = 'sha256:${await sha256.bind(artifact.openRead()).first}';
        final hub = await registry.registerArtifact(
          artifact.path,
          ServerReferenceInput.hub(
            registry: 'https://hub.example',
            namespace: 'local',
            name: 'demo',
            version: '1.0.0',
            versionDigest: 'sha256:${List.filled(64, 'a').join()}',
            hubArtifactId: 'artifact-1',
          ),
          const RegistrationPolicy(),
          expectedMetadata: ArtifactExpectedMetadata(
            digest: digest,
            size: await artifact.length(),
            name: 'demo',
            version: '1.0.0',
          ),
        );

        expect(imported.id, isNot(hub.id));
        expect(imported.artifactDigest, hub.artifactDigest);
        expect(await artifacts.list(), hasLength(1));
        final contentFile = File((await artifacts.list()).single.filePath);
        expect(await contentFile.exists(), isTrue);

        final firstRemoval = await registry.removeServer(imported.id);
        expect(firstRemoval.artifactRemoved, isFalse);
        expect(await contentFile.exists(), isTrue);
        final lastRemoval = await registry.removeServer(hub.id);
        expect(lastRemoval.artifactRemoved, isTrue);
        expect(await contentFile.exists(), isFalse);
      },
    );

    test(
      'same source with a different digest fails without partial state',
      () async {
        final reference = ServerReferenceInput.local(
          kind: 'import',
          namespace: 'local',
          name: 'demo',
          version: '1.0.0',
        );
        final original = await registry.registerArtifact(
          artifact.path,
          reference,
          const RegistrationPolicy(),
        );
        final changed = await _createArtifact(root, marker: 'two');

        await expectLater(
          registry.registerArtifact(
            changed.path,
            reference,
            const RegistrationPolicy(),
          ),
          throwsA(
            isA<ArtifactOperationException>().having(
              (error) => error.code,
              'code',
              'ARTIFACT_SOURCE_CONFLICT',
            ),
          ),
        );
        expect((await servers.list()).single.id, original.id);
        expect(await artifacts.list(), hasLength(1));
        expect(await operations.list(), isEmpty);
      },
    );

    test('accepts a bare entrypoint resolved from PATH', () async {
      final nodeArtifact = await _createArtifact(
        root,
        marker: 'node-entrypoint',
        entrypoint: 'node',
        files: const {'dist/index.js': 'console.log("ready");'},
      );

      final registered = await registry.registerArtifact(
        nodeArtifact.path,
        ServerReferenceInput.local(
          kind: 'import',
          namespace: 'local',
          name: 'demo',
          version: '1.0.0',
        ),
        const RegistrationPolicy(),
      );

      expect(registered.state, 'available');
      expect(await artifacts.list(), hasLength(1));
      expect(await servers.list(), hasLength(1));
      expect(await operations.list(), isEmpty);
    });

    test('rejects a missing path-like entrypoint', () async {
      final invalidArtifact = await _createArtifact(
        root,
        marker: 'missing-path-entrypoint',
        entrypoint: 'bin/missing',
        files: const {'dist/index.js': 'console.log("ready");'},
      );

      await expectLater(
        registry.registerArtifact(
          invalidArtifact.path,
          ServerReferenceInput.local(
            kind: 'import',
            namespace: 'local',
            name: 'demo',
            version: '1.0.0',
          ),
          const RegistrationPolicy(),
        ),
        throwsA(
          isA<ArtifactOperationException>().having(
            (error) => error.code,
            'code',
            'ARTIFACT_INVALID',
          ),
        ),
      );

      expect(await artifacts.list(), isEmpty);
      expect(await servers.list(), isEmpty);
      expect(await operations.list(), isEmpty);
    });

    test('protected and Tool-referenced Servers cannot be removed', () async {
      final builtin = await registry.registerArtifact(
        artifact.path,
        ServerReferenceInput.builtin(
          bundleFamily: 'embedded',
          bundleId: 'bundle-1',
          key: 'demo',
          namespace: 'local',
          name: 'demo',
          version: '1.0.0',
        ),
        const RegistrationPolicy(
          protected: true,
          managedBy: 'agentos-embedded',
        ),
      );
      await expectLater(
        registry.removeServer(builtin.id),
        throwsA(
          isA<ArtifactOperationException>().having(
            (error) => error.code,
            'code',
            'SERVER_PROTECTED',
          ),
        ),
      );

      final imported = await registry.registerArtifact(
        artifact.path,
        ServerReferenceInput.local(
          kind: 'import',
          namespace: 'local',
          name: 'demo',
          version: '1.0.0',
        ),
        const RegistrationPolicy(),
      );
      await tools.add(
        ToolDao(
          id: 'tool-1',
          alias: 'tool-1',
          tag: '1.0.0',
          host: '127.0.0.1',
          port: 9010,
          apiKey: 'secret',
          status: 'notRunning',
          serverId: imported.id,
        ),
      );
      await expectLater(
        registry.removeServer(imported.id),
        throwsA(
          isA<ArtifactOperationException>().having(
            (error) => error.code,
            'code',
            'SERVER_IN_USE',
          ),
        ),
      );
    });
  });

  test(
    'Tool materialization atomically updates content and preserves identity',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'materialization_test_',
      );
      try {
        final first = await _createArtifact(root, marker: 'first');
        final second = await _createArtifact(root, marker: 'second');
        final tools = _MemoryStorage<ToolDao>((value) => value.id);
        final operations = _MemoryStorage<ArtifactOperationDao>(
          (value) => value.id,
        );
        final tool = ToolDao(
          id: 'tool-1',
          alias: 'kept-alias',
          tag: '1.0.0',
          host: '127.0.0.1',
          port: 9123,
          apiKey: 'kept-secret',
          status: 'notRunning',
          serverId: 'server-1',
        );
        await tools.add(tool);
        final service = ToolMaterializationService(
          dataDir: root.path,
          tools: tools,
          operations: operations,
        );
        final firstDigest =
            'sha256:${await sha256.bind(first.openRead()).first}';
        final secondDigest =
            'sha256:${await sha256.bind(second.openRead()).first}';
        ServerModel server(File file, String digest) => ServerModel(
          id: 'server-1',
          alias: 'server',
          registry: '',
          namespace: 'local',
          name: 'demo',
          version: '1.0.0',
          internalId: digest,
          artifactDigest: digest,
          artifactFilePath: file.path,
          state: 'available',
        );

        await service.ensureMaterialized(tool, server(first, firstDigest));
        await service.ensureMaterialized(tool, server(second, secondDigest));

        final persisted = await tools.get(tool.id);
        expect(persisted!.materializedArtifactDigest, secondDigest);
        expect(persisted.alias, 'kept-alias');
        expect(persisted.apiKey, 'kept-secret');
        expect(persisted.port, 9123);
        expect(
          await File(
            p.join(root.path, 'tools', tool.id, 'bin', 'demo'),
          ).readAsString(),
          'second',
        );
        expect(await operations.list(), isEmpty);
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'Tool materialization restores the previous digest when stage persistence fails',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'materialization_rollback_test_',
      );
      try {
        final first = await _createArtifact(root, marker: 'rollback-first');
        final second = await _createArtifact(root, marker: 'rollback-second');
        final tools = _MemoryStorage<ToolDao>((value) => value.id);
        final initialOperations = _MemoryStorage<ArtifactOperationDao>(
          (value) => value.id,
        );
        final tool = ToolDao(
          id: 'tool-rollback',
          alias: 'tool-rollback',
          tag: '1.0.0',
          host: '127.0.0.1',
          port: 9123,
          apiKey: 'secret',
          status: 'notRunning',
          serverId: 'server-rollback',
        );
        await tools.add(tool);
        final firstDigest =
            'sha256:${await sha256.bind(first.openRead()).first}';
        final secondDigest =
            'sha256:${await sha256.bind(second.openRead()).first}';
        ServerModel server(File file, String digest) => ServerModel(
          id: 'server-rollback',
          alias: 'server',
          registry: '',
          namespace: 'local',
          name: 'demo',
          version: '1.0.0',
          internalId: digest,
          artifactDigest: digest,
          artifactFilePath: file.path,
          state: 'available',
        );
        await ToolMaterializationService(
          dataDir: root.path,
          tools: tools,
          operations: initialOperations,
        ).ensureMaterialized(tool, server(first, firstDigest));

        final failingOperations = _FailingOperationStorage('toolUpdated');
        await expectLater(
          ToolMaterializationService(
            dataDir: root.path,
            tools: tools,
            operations: failingOperations,
          ).ensureMaterialized(tool, server(second, secondDigest)),
          throwsA(isA<ArtifactOperationException>()),
        );

        final persisted = await tools.get(tool.id);
        expect(persisted!.materializedArtifactDigest, firstDigest);
        expect(
          await File(
            p.join(root.path, 'tools', tool.id, 'bin', 'demo'),
          ).readAsString(),
          'rollback-first',
        );
        expect(await failingOperations.list(), isEmpty);
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'builtin reconcile creates, retires, restores, and rejects invalid desired state atomically',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'builtin_reconcile_test_',
      );
      try {
        final artifact = await _createArtifact(root, marker: 'builtin');
        final digest = 'sha256:${await sha256.bind(artifact.openRead()).first}';
        final artifacts = _MemoryStorage<ArtifactDao>((value) => value.digest);
        final servers = _MemoryStorage<ServerDao>((value) => value.id);
        final operations = _MemoryStorage<ArtifactOperationDao>(
          (value) => value.id,
        );
        final bundles = _MemoryStorage<BuiltinBundleDao>(
          (value) => value.bundleFamily,
        );
        final content = _CountingArtifactStorage(root.path);
        final registry = ArtifactRegistryService(
          content: content,
          artifacts: artifacts,
          servers: servers,
          operations: operations,
        );
        final service = BuiltinReconcileService(
          registry: registry,
          content: content,
          servers: servers,
          bundles: bundles,
        );
        final item = BuiltinItemInput(
          key: 'demo',
          path: artifact.path,
          expectedDigest: digest,
          expectedSize: await artifact.length(),
        );

        final created = await service.reconcile(
          bundleFamily: 'embedded',
          bundleId: 'bundle-1',
          items: [item],
        );
        expect(created.created, ['demo']);
        expect(content.copyCount, 1);
        final serverId = (await servers.list()).single.id;
        (await servers.get(serverId))!.alias = 'preserved';
        await servers.update((await servers.get(serverId))!);

        final unchanged = await service.reconcile(
          bundleFamily: 'embedded',
          bundleId: 'bundle-1',
          items: [item],
        );
        expect(unchanged.reused, ['demo']);
        expect(content.copyCount, 1);

        final storedArtifact = File(content.pathForDigest(digest));
        await storedArtifact.delete();
        final repaired = await service.reconcile(
          bundleFamily: 'embedded',
          bundleId: 'bundle-1',
          items: [item],
        );
        expect(repaired.reused, ['demo']);
        expect(content.copyCount, 2);
        expect(await storedArtifact.exists(), isTrue);

        final retired = await service.reconcile(
          bundleFamily: 'embedded',
          bundleId: 'bundle-2',
          items: const [],
        );
        expect(retired.retired, ['demo']);
        expect((await servers.get(serverId))!.state, 'retired');

        final restored = await service.reconcile(
          bundleFamily: 'embedded',
          bundleId: 'bundle-3',
          items: [item],
        );
        expect(restored.reused, ['demo']);
        expect((await servers.get(serverId))!.state, 'available');
        expect((await servers.get(serverId))!.alias, 'preserved');

        await expectLater(
          service.reconcile(
            bundleFamily: 'embedded',
            bundleId: 'bundle-invalid',
            items: [
              item,
              BuiltinItemInput(
                key: 'bad',
                path: artifact.path,
                expectedDigest: 'sha256:${List.filled(64, '0').join()}',
                expectedSize: await artifact.length(),
              ),
            ],
          ),
          throwsA(isA<ArtifactOperationException>()),
        );
        expect((await bundles.get('embedded'))!.activeBundleId, 'bundle-3');
        expect((await servers.get(serverId))!.builtinBundleId, 'bundle-3');
        expect((await servers.list()), hasLength(1));
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'builtin reconcile rollback preserves a concurrently registered Hub Server',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'builtin_reconcile_rollback_test_',
      );
      try {
        final artifact = await _createArtifact(root, marker: 'builtin-fail');
        final digest = 'sha256:${await sha256.bind(artifact.openRead()).first}';
        final artifacts = _MemoryStorage<ArtifactDao>((value) => value.digest);
        final servers = _MemoryStorage<ServerDao>((value) => value.id);
        final operations = _MemoryStorage<ArtifactOperationDao>(
          (value) => value.id,
        );
        final unrelated = _server(
          id: 'hub-concurrent',
          sourceKind: 'hub',
          sourceKey: 'hub|demo|1.0.0',
        );
        final bundles = _FailingBundleStorage(
          beforeFailure: () => servers.add(unrelated),
        );
        final content = ArtifactStorage(root.path);
        final registry = ArtifactRegistryService(
          content: content,
          artifacts: artifacts,
          servers: servers,
          operations: operations,
        );
        final service = BuiltinReconcileService(
          registry: registry,
          content: content,
          servers: servers,
          bundles: bundles,
        );

        await expectLater(
          service.reconcile(
            bundleFamily: 'embedded',
            bundleId: 'bundle-fail',
            items: [
              BuiltinItemInput(
                key: 'demo',
                path: artifact.path,
                expectedDigest: digest,
                expectedSize: await artifact.length(),
              ),
            ],
          ),
          throwsA(isA<StateError>()),
        );

        expect(await servers.get(unrelated.id), isNotNull);
        expect(
          (await servers.list()).where(
            (server) => server.sourceKind == 'builtin',
          ),
          isEmpty,
        );
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'builtin reconcile recovery restores only its family snapshot',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'builtin_reconcile_recovery_test_',
      );
      try {
        final artifacts = _MemoryStorage<ArtifactDao>((value) => value.digest);
        final servers = _MemoryStorage<ServerDao>((value) => value.id);
        final operations = _MemoryStorage<ArtifactOperationDao>(
          (value) => value.id,
        );
        final bundles = _MemoryStorage<BuiltinBundleDao>(
          (value) => value.bundleFamily,
        );
        final previous = _server(
          id: 'builtin-previous',
          sourceKind: 'builtin',
          sourceKey: 'embedded|demo',
          bundleFamily: 'embedded',
          builtinKey: 'demo',
        );
        final created = _server(
          id: 'builtin-created',
          sourceKind: 'builtin',
          sourceKey: 'embedded|new',
          bundleFamily: 'embedded',
          builtinKey: 'new',
        );
        final unrelated = _server(
          id: 'import-concurrent',
          sourceKind: 'import',
          sourceKey: 'local|demo|1.0.0',
        );
        await servers.add(created);
        await servers.add(unrelated);
        await operations.add(
          ArtifactOperationDao(
            id: 'builtin-operation',
            type: 'builtinReconcile',
            stage: 'created',
            sourceKind: 'builtin',
            sourceKey: 'embedded',
            payloadJson: jsonEncode({
              'bundleFamily': 'embedded',
              'desiredBundleId': 'bundle-new',
              'familyServers': [_serverJson(previous)],
              'createdServerIds': [created.id],
              'previousBundle': null,
            }),
            createdAt: DateTime.utc(2026, 8, 6),
            updatedAt: DateTime.utc(2026, 8, 6),
          ),
        );
        final content = ArtifactStorage(root.path);
        final registry = ArtifactRegistryService(
          content: content,
          artifacts: artifacts,
          servers: servers,
          operations: operations,
        );
        final service = BuiltinReconcileService(
          registry: registry,
          content: content,
          servers: servers,
          bundles: bundles,
        );

        await service.recover();

        expect(await servers.get(previous.id), isNotNull);
        expect(await servers.get(created.id), isNull);
        expect(await servers.get(unrelated.id), isNotNull);
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );
}

Future<File> _createArtifact(
  Directory root, {
  required String marker,
  String entrypoint = 'bin/demo',
  Map<String, String> files = const {'bin/demo': ''},
}) async {
  final source = Directory(p.join(root.path, 'source-$marker'));
  await source.create(recursive: true);
  for (final entry in files.entries) {
    final file = File(p.join(source.path, entry.key));
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value.isEmpty ? marker : entry.value);
  }
  await File(p.join(source.path, 'Opentoolfile.json')).writeAsString('''
{"name":"demo","tag":"1.0.0","os":"linux","cpuArch":"arm64","build":{"args":{},"runs":[]},"run":{"envs":{},"workdir":".","entrypoint":"$entrypoint","cmds":[]}}
''');
  final output = File(p.join(root.path, '$marker.ots'));
  await ZipUtil.zipDirectory(source.path, output.path);
  return output;
}

class _MemoryStorage<T> implements Storage<T> {
  final String Function(T value) keyOf;
  final Map<String, T> values = {};
  _MemoryStorage(this.keyOf);

  @override
  Future<void> add(T value) async => values[keyOf(value)] = value;
  @override
  Future<T?> get(String id) async => values[id];
  @override
  Future<List<T>> list() async => values.values.toList();
  @override
  Future<T?> remove(String id) async => values.remove(id);
  @override
  Future<void> update(T value) async => values[keyOf(value)] = value;
}

class _CountingArtifactStorage extends ArtifactStorage {
  _CountingArtifactStorage(super.dataDir);

  var copyCount = 0;

  @override
  Future<ArtifactWriteResult> copyToPart(String sourcePath) {
    copyCount++;
    return super.copyToPart(sourcePath);
  }
}

class _FailingBundleStorage extends _MemoryStorage<BuiltinBundleDao> {
  final Future<void> Function() beforeFailure;
  var failed = false;

  _FailingBundleStorage({required this.beforeFailure})
    : super((value) => value.bundleFamily);

  @override
  Future<void> update(BuiltinBundleDao value) async {
    if (!failed) {
      failed = true;
      await beforeFailure();
      throw StateError('bundle persistence failed');
    }
    await super.update(value);
  }
}

class _FailingOperationStorage extends _MemoryStorage<ArtifactOperationDao> {
  final String failingStage;
  var failed = false;

  _FailingOperationStorage(this.failingStage) : super((value) => value.id);

  @override
  Future<void> update(ArtifactOperationDao value) async {
    if (!failed && value.stage == failingStage) {
      failed = true;
      throw StateError('operation stage persistence failed');
    }
    await super.update(value);
  }
}

ServerDao _server({
  required String id,
  required String sourceKind,
  required String sourceKey,
  String? bundleFamily,
  String? builtinKey,
}) => ServerDao(
  id: id,
  alias: id,
  namespace: 'local',
  name: 'demo',
  version: '1.0.0',
  artifactDigest: 'sha256:${List.filled(64, 'a').join()}',
  sourceKind: sourceKind,
  sourceKey: sourceKey,
  builtinBundleFamily: bundleFamily,
  builtinBundleId: bundleFamily == null ? null : 'bundle-old',
  builtinKey: builtinKey,
  protected: sourceKind == 'builtin',
  managedBy: sourceKind == 'builtin' ? 'agentos-embedded' : 'user',
  state: 'available',
  createdAt: DateTime.utc(2026, 8, 6),
);

Map<String, dynamic> _serverJson(ServerDao server) => {
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
