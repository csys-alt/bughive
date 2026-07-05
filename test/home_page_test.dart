import 'package:bughive/bootstrap/env.g.dart';
import 'package:bughive/bootstrap/providers.dart';
import 'package:bughive/resources/pages/home_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nylo_framework/nylo_framework.dart';

void main() {
  NyTest.init();

  nySetUpAll(() async {
    NyEnvRegistry.register(getter: Env.get);
    await setupApplication(providers);
  });

  nyGroup('HomePage', () {
    nyWidgetTest('displays workspace header and add repository action', (
      tester,
    ) async {
      await tester.pumpNyWidgetSimple(HomePage());

      expect(find.text('BugHive'), findsOneWidget);
      expect(
        find.text('A quiet workspace for bugs, notes, and GitHub decisions.'),
        findsOneWidget,
      );
      expect(find.text('Add repository'), findsOneWidget);
    });

    nyWidgetTest('shows empty repository state', (tester) async {
      await tester.pumpNyWidgetSimple(HomePage());
      await tester.pump();

      expect(find.text('No repositories'), findsOneWidget);
    });
  });
}
