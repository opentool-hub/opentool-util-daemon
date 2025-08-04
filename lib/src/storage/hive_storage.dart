import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'dao.dart';
import 'storage.dart';

class HiveStorage implements Storage {
  static const String _boxName = 'opentool_servers';

  late Box<OpenToolServerDao> _box;

  Future<void> init() async {
    Hive.registerAdapter(OpenToolServerDaoAdapter());

    final dir = Directory.current.path;
    final hivePath = p.join(dir, '.opentool_data');
    await Directory(hivePath).create(recursive: true);

    Hive.init(hivePath);
    _box = await Hive.openBox<OpenToolServerDao>(_boxName);
  }

  @override
  Future<void> add(OpenToolServerDao serverDao) async {
    await _box.put(serverDao.id, serverDao);
  }

  @override
  Future<OpenToolServerDao?> get(String id) async {
    return _box.get(id);
  }

  @override
  Future<void> update(OpenToolServerDao serverDao) async {
    await _box.put(serverDao.id, serverDao);
  }

  @override
  Future<OpenToolServerDao?> remove(String id) async {
    final server = _box.get(id);
    await _box.delete(id);
    return server;
  }

  @override
  Future<List<OpenToolServerDao>> list() async {
    return _box.values.toList();
  }
}