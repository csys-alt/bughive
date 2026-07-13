import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports device connectivity. `isOnline` is a cached snapshot updated from
/// the platform stream; treat it as best-effort — a write that fails on a
/// false-positive simply stays queued.
abstract class ConnectivityService {
  bool get isOnline;
  Stream<bool> get onStatusChange;
  Future<void> start();
  void dispose();
}

class ConnectivityPlusService implements ConnectivityService {
  ConnectivityPlusService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isOnline = true;

  @override
  bool get isOnline => _isOnline;

  @override
  Stream<bool> get onStatusChange => _controller.stream;

  @override
  Future<void> start() async {
    _isOnline = _resultsOnline(await _connectivity.checkConnectivity());
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final next = _resultsOnline(results);
      if (next == _isOnline) return;
      _isOnline = next;
      _controller.add(next);
    });
  }

  bool _resultsOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
