import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import 'dao.dart';
import 'storage.dart';

const artifactsBoxName = 'artifacts_v1';
const serversBoxName = 'servers_v2';
const toolsBoxName = 'tools_v2';
const artifactOperationsBoxName = 'artifact_operations_v1';
const schemaMetaBoxName = 'schema_meta_v1';
const builtinBundlesBoxName = 'builtin_bundles_v1';
const apiKeysBoxName = 'api_keys';

void registerRegistryAdapters() {
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(ApiKeyDaoAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(ArtifactDaoAdapter());
  if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(ServerDaoAdapter());
  if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(ToolDaoAdapter());
  if (!Hive.isAdapterRegistered(7)) {
    Hive.registerAdapter(ArtifactOperationDaoAdapter());
  }
  if (!Hive.isAdapterRegistered(8))
    Hive.registerAdapter(SchemaMetaDaoAdapter());
  if (!Hive.isAdapterRegistered(9)) {
    Hive.registerAdapter(BuiltinBundleDaoAdapter());
  }
}

class RegistryStorageBundle {
  final String dataDir;
  late final HiveArtifactStorage artifacts;
  late final RegistryServerStorage servers;
  late final RegistryToolStorage tools;
  late final HiveArtifactOperationStorage operations;
  late final HiveSchemaMetaStorage schemaMeta;
  late final HiveBuiltinBundleStorage builtinBundles;
  late final HiveApiKeyStorage apiKeys;

  RegistryStorageBundle(this.dataDir);

  Future<void> init() async {
    final dbPath = p.join(dataDir, 'db');
    await Directory(dbPath).create(recursive: true);
    Hive.init(dbPath);
    registerRegistryAdapters();
    artifacts = HiveArtifactStorage(await _open<ArtifactDao>(artifactsBoxName));
    servers = RegistryServerStorage(await _open<ServerDao>(serversBoxName));
    tools = RegistryToolStorage(await _open<ToolDao>(toolsBoxName));
    operations = HiveArtifactOperationStorage(
      await _open<ArtifactOperationDao>(artifactOperationsBoxName),
    );
    schemaMeta = HiveSchemaMetaStorage(
      await _open<SchemaMetaDao>(schemaMetaBoxName),
    );
    builtinBundles = HiveBuiltinBundleStorage(
      await _open<BuiltinBundleDao>(builtinBundlesBoxName),
    );
    apiKeys = HiveApiKeyStorage(await _open<ApiKeyDao>(apiKeysBoxName));
  }

  Future<Box<T>> _open<T>(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box<T>(name);
    return Hive.openBox<T>(name);
  }
}

abstract class HiveStorage<T> implements Storage<T> {
  final Box<T> box;

  HiveStorage(this.box);

  String keyOf(T value);

  @override
  Future<void> add(T value) => box.put(keyOf(value), value);

  @override
  Future<T?> get(String id) async => box.get(id);

  @override
  Future<List<T>> list() async => box.values.toList(growable: false);

  @override
  Future<T?> remove(String id) async {
    final value = box.get(id);
    await box.delete(id);
    return value;
  }

  @override
  Future<void> update(T value) => box.put(keyOf(value), value);
}

class HiveArtifactStorage extends HiveStorage<ArtifactDao> {
  HiveArtifactStorage(super.box);

  @override
  String keyOf(ArtifactDao value) => value.digest;
}

class RegistryServerStorage extends HiveStorage<ServerDao> {
  RegistryServerStorage(super.box);

  @override
  String keyOf(ServerDao value) => value.id;
}

class RegistryToolStorage extends HiveStorage<ToolDao> {
  RegistryToolStorage(super.box);

  @override
  String keyOf(ToolDao value) => value.id;
}

class HiveArtifactOperationStorage extends HiveStorage<ArtifactOperationDao> {
  HiveArtifactOperationStorage(super.box);

  @override
  String keyOf(ArtifactOperationDao value) => value.id;
}

class HiveSchemaMetaStorage extends HiveStorage<SchemaMetaDao> {
  static const activeKey = 'active';

  HiveSchemaMetaStorage(super.box);

  @override
  String keyOf(SchemaMetaDao value) => activeKey;
}

class HiveBuiltinBundleStorage extends HiveStorage<BuiltinBundleDao> {
  HiveBuiltinBundleStorage(super.box);

  @override
  String keyOf(BuiltinBundleDao value) => value.bundleFamily;
}

class HiveApiKeyStorage extends HiveStorage<ApiKeyDao> {
  HiveApiKeyStorage(super.box);

  @override
  String keyOf(ApiKeyDao value) => value.id;
}

class DeferredHiveApiKeyStorage implements Storage<ApiKeyDao> {
  final String dataDir;
  HiveApiKeyStorage? _storage;

  DeferredHiveApiKeyStorage(this.dataDir);

  Future<HiveApiKeyStorage> _getStorage() async {
    final current = _storage;
    if (current != null) return current;
    final dbPath = p.join(dataDir, 'db');
    await Directory(dbPath).create(recursive: true);
    Hive.init(dbPath);
    registerRegistryAdapters();
    final box = Hive.isBoxOpen(apiKeysBoxName)
        ? Hive.box<ApiKeyDao>(apiKeysBoxName)
        : await Hive.openBox<ApiKeyDao>(apiKeysBoxName);
    return _storage = HiveApiKeyStorage(box);
  }

  @override
  Future<void> add(ApiKeyDao value) async => (await _getStorage()).add(value);

  @override
  Future<ApiKeyDao?> get(String id) async => (await _getStorage()).get(id);

  @override
  Future<List<ApiKeyDao>> list() async => (await _getStorage()).list();

  @override
  Future<ApiKeyDao?> remove(String id) async =>
      (await _getStorage()).remove(id);

  @override
  Future<void> update(ApiKeyDao value) async =>
      (await _getStorage()).update(value);
}
