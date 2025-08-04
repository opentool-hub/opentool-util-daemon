import 'dao.dart';

abstract class Storage {
  Future<void> add(OpenToolServerDao serverDao);
  Future<OpenToolServerDao?> get(String id);
  Future<void> update(OpenToolServerDao serverDao);
  Future<OpenToolServerDao?> remove(String id);
  Future<List<OpenToolServerDao>> list();
}