import 'dart:async';
import 'package:bughive/app/services/offline/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeConnectivityService implements ConnectivityService {
  bool _online = true;
  final _controller = StreamController<bool>.broadcast();
  @override
  bool get isOnline => _online;
  @override
  Stream<bool> get onStatusChange => _controller.stream;
  @override
  Future<void> start() async {}
  @override
  void dispose() => _controller.close();
  void emit(bool online) {
    _online = online;
    _controller.add(online);
  }
}

void main() {
  test('fake emits status transitions and updates isOnline', () async {
    final fake = FakeConnectivityService();
    expect(fake.isOnline, isTrue);
    final events = <bool>[];
    final sub = fake.onStatusChange.listen(events.add);
    fake.emit(false);
    fake.emit(true);
    await Future.delayed(Duration.zero);
    expect(fake.isOnline, isTrue);
    expect(events, [false, true]);
    await sub.cancel();
    fake.dispose();
  });
}
