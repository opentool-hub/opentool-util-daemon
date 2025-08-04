import 'model.dart';
import 'exception.dart';
import '../storage/dao.dart';
import '../storage/storage.dart';

class ManageService {
  final Storage storage;

  ManageService({required this.storage});

  Future<List<OpenToolServerModel>> list() async {
    List<OpenToolServerModel> serverModelList = (await storage.list()).map((dao) => OpenToolServerModel.fromDao(dao)).toList();
    return serverModelList;
  }

  Future<OpenToolServerModel> get(String id) async {
    OpenToolServerDao? serverDao = await storage.get(id);
    if (serverDao == null) throw ServerNotFoundException(id);
    return OpenToolServerModel.fromDao(serverDao);
  }

  Future<void> add(OpenToolServerModel serverModel) async {
    OpenToolServerDao serverDao = serverModel.toDao();
    await storage.add(serverDao);
  }

  Future<void> updatePid(String id, int? pid) async {
    OpenToolServerDao? serverDao = await storage.get(id);
    if (serverDao == null) throw ServerNotFoundException(id);
    serverDao.pid = pid;
    await storage.update(serverDao);
  }

  Future<void> rename(String id, String name) async {
    OpenToolServerDao? serverDao = await storage.get(id);
    if (serverDao == null) throw ServerNotFoundException(id);
    serverDao.name = name;
    await storage.update(serverDao);
  }

  Future<String> remove(String id) async {
    await storage.remove(id);
    return id;
  }
}