import '/resources/pages/add_repository_page.dart';
import '/resources/pages/repository_detail_page.dart';
import '/resources/pages/create_log_page.dart';
import '/resources/pages/home_page.dart';
import '/resources/pages/log_detail_page.dart';
import '/resources/pages/login_page.dart';
import '/resources/pages/not_found_page.dart';
import '/resources/pages/profile_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

dynamic appRouter() => nyRoutes((router) {
  router.add(LoginPage.path).initialRoute();
  router.add(HomePage.path);
  router.add(AddRepositoryPage.path);
  router.add(RepositoryDetailPage.path);
  router.add(CreateLogPage.path);
  router.add(LogDetailPage.path);
  router.add(ProfilePage.path);

  router.add(NotFoundPage.path).unknownRoute();
});
