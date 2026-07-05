import 'package:nylo_framework/nylo_framework.dart';

class PushNotificationsProvider implements NyProvider {

  @override
  setup(Nylo nylo) async {
    nylo.useLocalNotifications();
    return nylo;
  }

  @override
  boot(Nylo nylo) async {

  }
}
