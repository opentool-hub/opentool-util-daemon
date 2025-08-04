class ServerNotFoundException implements Exception {
  String id;
  late String message ;

  ServerNotFoundException(this.id) {
    this.message = 'Server with id $id not found';
  }

  @override
  String toString() {
    return 'ServerNotFoundException: $message';
  }
}