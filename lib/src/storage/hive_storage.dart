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
    await _box.put(serverDao.id, serverDao);
  }

  @override
  Future<ServerDao?> get(String id) async {
    return _box.get(id);
  }

  @override
  Future<void> update(ServerDao serverDao) async {
    await _box.put(serverDao.id, serverDao);
  }

  @override
  Future<ServerDao?> remove(String id) async {
    final server = _box.get(id);
    await _box.delete(id);
    return server;
  }

  @override
  Future<List<ServerDao>> list() async {
    return _box.values.toList();
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