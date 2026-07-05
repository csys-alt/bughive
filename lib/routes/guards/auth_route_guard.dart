import '/resources/pages/login_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

class AuthRouteGuard extends NyRouteGuard {
  AuthRouteGuard();

  @override
  Future<GuardResult> onBefore(RouteContext context) async {
    bool isLoggedIn = await Auth.isAuthenticated();
    if (!isLoggedIn) {
      return redirect(LoginPage.path);
    }

    return next();
  }
}
