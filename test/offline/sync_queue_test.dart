import 'package:bughive/app/services/offline/key_value_store.dart';
import 'package:bughive/app/services/offline/sync_operation.dart';
import 'package:bughive/app/services/offline/sync_queue.dart';
import 'package:flutter_test/flutter_test.dart';

SyncOperation _op(String opId, SyncOpType type, String logId) => SyncOperation(
      opId: opId,
      type: type,
      payload: type == SyncOpType.createAttachment
          ? {"id": opId, "log_id": logId}
          : {"id": logId},
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late InMemoryKeyValueStore store;
  late SyncQueue queue;

  setUp(() {
    store = InMemoryKeyValueStore();
    queue = SyncQueue(store, "user-1");
  });

  test('enqueue preserves FIFO order and survives reload', () async {
    await queue.enqueue(_op("a", SyncOpType.createLog, "log-1"));
    await queue.enqueue(_op("b", SyncOpType.updateLog, "log-1"));
    final reloaded = SyncQueue(store, "user-1");
    final all = await reloaded.all();
    expect(all.map((o) => o.opId), ["a", "b"]);
  });

  test('remove deletes by opId', () async {
    await queue.enqueue(_op("a", SyncOpType.createLog, "log-1"));
    await queue.enqueue(_op("b", SyncOpType.updateLog, "log-1"));
    await queue.remove("a");
    final all = await queue.all();
    expect(all.map((o) => o.opId), ["b"]);
  });

  test('markError records message without removing op', () async {
    await queue.enqueue(_op("a", SyncOpType.createLog, "log-1"));
    await queue.markError("a", "boom");
    final all = await queue.all();
    expect(all.single.error, "boom");
  });

  test('cancelCreateFor removes createLog + its attachments, no delete left',
      () async {
    await queue.enqueue(_op("a", SyncOpType.createLog, "log-1"));
    await queue.enqueue(_op("img", SyncOpType.createAttachment, "log-1"));
    await queue.enqueue(_op("b", SyncOpType.createLog, "log-2"));
    await queue.cancelCreateFor("log-1");
    final all = await queue.all();
    expect(all.map((o) => o.opId), ["b"]);
  });

  test('hasPendingCreate reflects queue', () async {
    await queue.enqueue(_op("a", SyncOpType.createLog, "log-1"));
    expect(await queue.hasPendingCreate("log-1"), isTrue);
    expect(await queue.hasPendingCreate("log-2"), isFalse);
  });

  test('pending notifier tracks count', () async {
    await queue.enqueue(_op("a", SyncOpType.createLog, "log-1"));
    expect(queue.pending.value, 1);
    await queue.remove("a");
    expect(queue.pending.value, 0);
  });
}
