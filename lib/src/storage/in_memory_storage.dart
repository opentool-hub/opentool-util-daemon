import 'dao.dart';
import 'storage.dart';

class InMemoryServerStorage implements Storage<ServerDao> {
  final List<ServerDao> _storage = [];

  Future<void> add(ServerDao server) async {
    final index = _storage.indexWhere((s) => s.id == server.id);
    if (index != -1) {
      _storage[index] = server;
      return;
    }
    _storage.add(server);
  }

  Future<void> update(ServerDao server) async {
    int index = _storage.indexWhere((s) => s.id == server.id);
    if (index != -1) {
      _storage[index] = server;
    }
  }

  Future<ServerDao?> remove(String id) async {
    try {
      ServerDao? serverDao = _storage.firstWhere((s) => s.id == id);
      _storage.removeWhere((s) => s.id == id);
      return serverDao;
    } catch (e) {
      return null;
    }
  }

  Future<ServerDao?> get(String id) async {
    try {
      return _storage.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<ServerDao>> list() async {
    return _storage;
  }
}

class InMemoryToolStorage implements Storage<ToolDao> {
  final List<ToolDao> _storage = [];

  Future<void> add(ToolDao toolDao) async {
    final index = _storage.indexWhere((s) => s.id == toolDao.id);
    if (index != -1) {
      _storage[index] = toolDao;
      return;
    }
    _storage.add(toolDao);
  }

  Future<void> update(ToolDao toolDao) async {
    int index = _storage.indexWhere((s) => s.id == toolDao.id);
    if (index != -1) {
      _storage[index] = toolDao;
    }
  }

  Future<ToolDao?> remove(String id) async {
    try {
      ToolDao? toolDao = _storage.firstWhere((s) => s.id == id);
      _storage.removeWhere((s) => s.id == id);
      return toolDao;
    } catch (e) {
      return null;
    }
  }

  Future<ToolDao?> get(String id) async {
    try {
      return _storage.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<ToolDao>> list() async {
    return _storage;
  }
}
