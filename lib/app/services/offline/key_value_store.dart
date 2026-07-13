import 'package:nylo_framework/nylo_framework.dart';

abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class NyKeyValueStore implements KeyValueStore {
  @override
  Future<String?> read(String key) => NyStorage.read<String>(key);

  @override
  Future<void> write(String key, String value) => NyStorage.save(key, value);

  @override
  Future<void> delete(String key) => NyStorage.delete(key);
}

class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}
