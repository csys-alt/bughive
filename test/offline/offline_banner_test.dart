// test/offline/offline_banner_test.dart
import 'package:bughive/resources/widgets/offline_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'connectivity_service_test.dart' show FakeConnectivityService;

void main() {
  testWidgets('shows bar when offline, hides when online', (tester) async {
    final conn = FakeConnectivityService()..emit(false);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: OfflineBanner(connectivity: conn)),
    ));
    await tester.pump();
    expect(find.textContaining('offline'), findsOneWidget);
    conn.emit(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('offline'), findsNothing);
  });
}
