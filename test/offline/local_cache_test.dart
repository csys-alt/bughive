// test/offline/local_cache_test.dart
import 'package:bughive/app/models/engineering_log.dart';
import 'package:bughive/app/models/repository.dart';
import 'package:bughive/app/services/offline/key_value_store.dart';
import 'package:bughive/app/services/offline/local_cache.dart';
import 'package:flutter_test/flutter_test.dart';

EngineeringLog _log(String id, String repoId, String title) => EngineeringLog(
      id: id,
      repoId: repoId,
      userId: "u1",
      title: title,
      description: "d",
      type: EngineeringLogType.bug,
      severity: Severity.medium,
      environment: "env",
      labels: const [],
    );

void main() {
  late LocalCache cache;
  setUp(() => cache = LocalCache(InMemoryKeyValueStore(), "u1"));

  test('repos round-trip', () async {
    await cache.writeRepos([
      const Repository(id: "r1", githubRepoId: 1, owner: "o", name: "n", url: "u"),
    ]);
    final repos = await cache.readRepos();
    expect(repos.single.id, "r1");
    expect(repos.single.fullName, "o/n");
  });

  test('upsertLog inserts then replaces by id', () async {
    await cache.upsertLog(_log("l1", "r1", "first"));
    await cache.upsertLog(_log("l1", "r1", "second"));
    final logs = await cache.readLogs("r1");
    expect(logs.length, 1);
    expect(logs.single.title, "second");
  });

  test('removeLog drops the entry', () async {
    await cache.upsertLog(_log("l1", "r1", "x"));
    await cache.removeLog(_log("l1", "r1", "x"));
    expect(await cache.readLogs("r1"), isEmpty);
  });
}
