import '/app/providers/push_notifications_provider.dart';
import '/app/providers/app_provider.dart';
import '/app/providers/event_provider.dart';
import '/app/providers/route_provider.dart';
import 'package:nylo_framework/nylo_framework.dart';

/* Providers
|--------------------------------------------------------------------------
| Providers are booted when your application start.
| They are used to register services and perform setup tasks.
|
| Learn more: https://nylo.dev/docs/7.x/providers
|-------------------------------------------------------------------------- */

final Map<Type, NyProvider> providers = {
  AppProvider: AppProvider(),
  RouteProvider: RouteProvider(),
  EventProvider: EventProvider(),
  PushNotificationsProvider: PushNotificationsProvider(),
};
