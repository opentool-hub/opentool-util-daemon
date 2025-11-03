abstract class Storage<T> {
  Future<void> add(T value);
  Future<T?> get(String id);
  Future<void> update(T value);
  Future<T?> remove(String id);
  Future<List<T>> list();
}