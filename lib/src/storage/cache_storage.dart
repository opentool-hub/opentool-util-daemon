import 'hive_storage.dart';
import 'dao.dart';
import 'in_memory_storage.dart';
import 'storage.dart';

class CacheServerStorage implements Storage<ServerDao> {
  final InMemoryServerStorage _inMemory = InMemoryServerStorage();
  late HiveServerStorage _hive;
  bool _warmed = false;

  CacheServerStorage(HiveServerStorage hiveOpenToolServerStorage) {
    _hive = hiveOpenToolServerStorage;
  }

  Future<void> add(ServerDao serverDao) async {
    await _hive.add(serverDao);
    await _inMemory.add(serverDao);
  }

  Future<void> update(ServerDao serverDao) async {
    await _hive.update(serverDao);
    await _inMemory.update(serverDao);
  }

  Future<ServerDao?> remove(String id) async {
    ServerDao? serverDao = await _hive.remove(id);
    await _inMemory.remove(id);
    return serverDao;
  }

  Future<ServerDao?> get(String id) async {
    ServerDao? serverDao = await _inMemory.get(id);
    if (serverDao == null) {
      serverDao = await _hive.get(id);
      if (serverDao != null) {
        await _inMemory.add(serverDao);
      }
    }
    return serverDao;
  }

  @override
  Future<List<ServerDao>> list() async {
    if (!_warmed) {
      final serverDaoList = await _hive.list();
      for (final serverDao in serverDaoList) {
        await _inMemory.add(serverDao);
      }
      _warmed = true;
      return serverDaoList;
    }
    return _inMemory.list();
  }
}

class CacheToolStorage implements Storage<ToolDao> {
  final InMemoryToolStorage _inMemory = InMemoryToolStorage();
  late HiveToolStorage _hive;
  bool _warmed = false;

  CacheToolStorage(HiveToolStorage hiveToolStorage) {
    _hive = hiveToolStorage;
  }

  Future<void> add(ToolDao toolDao) async {
    await _hive.add(toolDao);
    await _inMemory.add(toolDao);
  }

  Future<void> update(ToolDao toolDao) async {
    await _hive.update(toolDao);
    await _inMemory.update(toolDao);
  }

  Future<ToolDao?> remove(String id) async {
    ToolDao? toolDao = await _hive.remove(id);
    await _inMemory.remove(id);
    return toolDao;
  }

  Future<ToolDao?> get(String id) async {
    ToolDao? toolDao = await _inMemory.get(id);
    if (toolDao == null) {
      toolDao = await _hive.get(id);
      if (toolDao != null) {
        await _inMemory.add(toolDao);
      }
    }
    return toolDao;
  }

  @override
  Future<List<ToolDao>> list() async {
    if (!_warmed) {
      final toolDaoList = await _hive.list();
      for (final toolDao in toolDaoList) {
        await _inMemory.add(toolDao);
      }
      _warmed = true;
      return toolDaoList;
    }
    return _inMemory.list();
  }
}
