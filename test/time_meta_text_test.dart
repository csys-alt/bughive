import 'package:bughive/resources/widgets/time_meta_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('future sync timestamps read as just now', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimeMetaText(
          syncAt: DateTime.now().add(const Duration(hours: 2)),
        ),
      ),
    );

    expect(find.text('Just now'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
