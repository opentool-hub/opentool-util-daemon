import 'dart:io';
import 'package:hive/hive.dart';
import 'package:opentool_daemon/src/utils/directory_util.dart';
import 'package:path/path.dart' as p;
import 'dao.dart';
import 'storage.dart';

String DB_PATH = '.opentool${Platform.pathSeparator}db';

class HiveInternalServerStorage implements Storage<InternalServerDao> {
  static const String _boxName = 'internal_servers';

  late Box<InternalServerDao> _box;

  Future<void> init() async {
    Hive.registerAdapter(InternalServerDaoAdapter());

    final dir = DirectoryUtil.getBaseDir();
    final hivePath = p.join(dir, DB_PATH);
    await Directory(hivePath).create(recursive: true);

    Hive.init(hivePath);
    _box = await Hive.openBox<InternalServerDao>(_boxName);
  }

  @override
  Future<void> add(InternalServerDao serverDao) async {
    await _box.put(serverDao.id, serverDao);
  }

  @override
  Future<InternalServerDao?> get(String id) async {
    return _box.get(id);
  }

  @override
  Future<void> update(InternalServerDao serverDao) async {
    await _box.put(serverDao.id, serverDao);
  }

  @override
  Future<InternalServerDao?> remove(String id) async {
    final server = _box.get(id);
    await _box.delete(id);
    return server;
  }

  @override
  Future<List<InternalServerDao>> list() async {
    return _box.values.toList();
  }
}

class HiveServerStorage implements Storage<ServerDao> {
  static const String _boxName = 'servers';

  late Box<ServerDao> _box;

  ServerDao _detach(ServerDao serverDao, {required String id}) {
    return ServerDao(
      id: id,
      alias: serverDao.alias,
      registry: serverDao.registry,
      repo: serverDao.repo,
      name: serverDao.name,
      tag: serverDao.tag,
      internalId: serverDao.internalId,
    );
  }

  Future<void> init() async {
    Hive.registerAdapter(ServerDaoAdapter());

    final dir = DirectoryUtil.getBaseDir();
    final hivePath = p.join(dir, DB_PATH);
    await Directory(hivePath).create(recursive: true);

    Hive.init(hivePath);
    _box = await Hive.openBox<ServerDao>(_boxName);
  }

  @override
  Future<void> add(ServerDao serverDao) async {
    await _box.put(serverDao.id, _detach(serverDao, id: serverDao.id));
  }

  @override
  Future<ServerDao?> get(String id) async {
    final direct = _box.get(id);
    if (direct != null) {
      if (direct.id != id) {
        final repaired = _detach(direct, id: id);
        await _box.put(id, repaired);
        return _detach(repaired, id: id);
      }
      return _detach(direct, id: id);
    }

    // Fallback: locate entries where the stored field id matches.
    final snapshot = _box.toMap();
    for (final entry in snapshot.entries) {
      final serverDao = entry.value;
      if (serverDao.id != id) continue;
      final repaired = _detach(serverDao, id: id);
      await _box.delete(entry.key);
      await _box.put(id, repaired);
      return _detach(repaired, id: id);
    }
    return null;
  }

  @override
  Future<void> update(ServerDao serverDao) async {
    final existingKey = serverDao.key;
    if (existingKey != null && existingKey != serverDao.id) {
      await _box.delete(existingKey);
    }
    await _box.put(serverDao.id, _detach(serverDao, id: serverDao.id));
  }

  @override
  Future<ServerDao?> remove(String id) async {
    final direct = _box.get(id);
    if (direct != null) {
      await _box.delete(id);
      return _detach(direct, id: id);
    }

    final snapshot = _box.toMap();
    for (final entry in snapshot.entries) {
      final serverDao = entry.value;
      if (serverDao.id != id) continue;
      await _box.delete(entry.key);
      return _detach(serverDao, id: id);
    }

    return null;
  }

  @override
  Future<List<ServerDao>> list() async {
    final snapshot = _box.toMap();
    final Map<String, ServerDao> byId = {};

    for (final entry in snapshot.entries) {
      final serverDao = entry.value;
      final id = serverDao.id;
      if (entry.key != id) {
        final repaired = _detach(serverDao, id: id);
        await _box.delete(entry.key);
        await _box.put(id, repaired);
        byId[id] = _detach(repaired, id: id);
        continue;
      }
      byId[id] = _detach(serverDao, id: id);
    }

    return byId.values.toList();
  }
}

class HiveToolStorage implements Storage<ToolDao> {
  static const String _boxName = 'tools';

  late Box<ToolDao> _box;

  Future<void> init() async {
    Hive.registerAdapter(ToolDaoAdapter());

    final dir = DirectoryUtil.getBaseDir();
    final hivePath = p.join(dir, DB_PATH);
    await Directory(hivePath).create(recursive: true);

    Hive.init(hivePath);
    _box = await Hive.openBox<ToolDao>(_boxName);
  }

  @override
  Future<void> add(ToolDao toolDao) async {
    await _box.put(toolDao.id, toolDao);
  }

  @override
  Future<ToolDao?> get(String id) async {
    return _box.get(id);
  }

  @override
  Future<void> update(ToolDao toolDao) async {
    await _box.put(toolDao.id, toolDao);
  }

  @override
  Future<ToolDao?> remove(String id) async {
    final tool = _box.get(id);
    await _box.delete(id);
    return tool;
  }

  @override
  Future<List<ToolDao>> list() async {
    return _box.values.toList();
  }
}

class HiveApiKeyStorage implements Storage<ApiKeyDao> {
  static const String _boxName = 'api_keys';
  static const int _typeId = 3;

  final String dataDir;

  HiveApiKeyStorage({required this.dataDir});

  bool _initialized = false;
  late Box<ApiKeyDao> _box;

  Future<void> _initIfNeeded() async {
    if (_initialized) return;
    if (!Hive.isAdapterRegistered(_typeId)) {
      Hive.registerAdapter(ApiKeyDaoAdapter());
    }
    if (Hive.isBoxOpen(_boxName)) {
      _box = Hive.box<ApiKeyDao>(_boxName);
    } else {
      final hivePath = p.join(dataDir, 'db');
      await Directory(hivePath).create(recursive: true);
      Hive.init(hivePath);
      _box = await Hive.openBox<ApiKeyDao>(_boxName);
    }
    _initialized = true;
  }

  @override
  Future<void> add(ApiKeyDao value) async {
    await _initIfNeeded();
    await _box.put(value.id, value);
  }

  @override
  Future<ApiKeyDao?> get(String id) async {
    await _initIfNeeded();
    return _box.get(id);
  }

  @override
  Future<void> update(ApiKeyDao value) async {
    await _initIfNeeded();
    await _box.put(value.id, value);
  }

  @override
  Future<ApiKeyDao?> remove(String id) async {
    await _initIfNeeded();
    final value = _box.get(id);
    await _box.delete(id);
    return value;
  }

  @override
  Future<List<ApiKeyDao>> list() async {
    await _initIfNeeded();
    return _box.values.toList();
  }
}
