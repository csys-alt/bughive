import 'package:bughive/bootstrap/env.g.dart';
import 'package:bughive/bootstrap/providers.dart';
import 'package:bughive/app/services/supabase_service.dart';
import 'package:bughive/resources/pages/login_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nylo_framework/nylo_framework.dart';

void main() {
  NyTest.init();

  nySetUpAll(() async {
    NyEnvRegistry.register(getter: Env.get);
    await setupApplication(providers);
  });

  nyGroup('BugHive Screens', () {
    nyWidgetTest('login screen matches the product entry point', (
      tester,
    ) async {
      await tester.pumpNyWidgetSimple(LoginPage());

      expect(find.text('BugHive'), findsOneWidget);
      expect(find.text('Engineering notes\nfor builders.'), findsOneWidget);
      expect(find.text('Continue with GitHub'), findsOneWidget);
      expect(find.text('Continue offline'), findsOneWidget);
    });
  });

  nyGroup('Routes', () {
    nyTest('registers BugHive routes', () async {
      expectRoutesExist([
        '/login',
        '/home',
        '/repositories/add',
        '/repository',
        '/logs/create',
        '/logs/detail',
        '/profile',
      ]);
    });
  });

  nyGroup('Environment', () {
    nyTest('keeps app environment available', () async {
      expectEnvSet('APP_NAME');
      expectEnvSet('APP_ENV');
      expectTestMode();
    });

    nyTest('normalizes Supabase project URL', () async {
      expect(
        SupabaseService.normalizeSupabaseUrl('demo.supabase.co'),
        'https://demo.supabase.co',
      );
    });
  });
}
