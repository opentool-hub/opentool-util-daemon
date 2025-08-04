import 'dao.dart';
import 'storage.dart';

class InMemoryStorage implements Storage {
  final List<OpenToolServerDao> _storage = [];

  Future<void> add(OpenToolServerDao server) async {
    _storage.add(server);
  }

  Future<void> update(OpenToolServerDao server) async {
    int index = _storage.indexWhere((s) => s.id == server.id);
    if (index != -1) {
      _storage[index] = server;
    }
  }

  Future<OpenToolServerDao?> remove(String id) async {
    try {
      OpenToolServerDao? serverDao = _storage.firstWhere((s) => s.id == id);
       _storage.removeWhere((s) => s.id == id);
       return serverDao;
    } catch (e) {
      return null;
    }
  }

  Future<OpenToolServerDao?> get(String id) async {
    try {
      return _storage.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<OpenToolServerDao>> list() async {
    return _storage;
  }
}