import '/app/events/authenticated_event.dart';
import '/app/events/logout_event.dart';
import 'package:nylo_framework/nylo_framework.dart';

/* Events
|--------------------------------------------------------------------------
| Add your "app/events" here.
| Events can be fired using: event<MyEvent>();
|
| Learn more: https://nylo.dev/docs/7.x/events
|-------------------------------------------------------------------------- */

final Map<Type, NyEvent> events = {
  LogoutEvent: LogoutEvent(),
  AuthenticatedEvent: AuthenticatedEvent(),
  };
