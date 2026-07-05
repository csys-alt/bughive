import 'package:nylo_framework/nylo_framework.dart';

/* Storage Keys
|--------------------------------------------------------------------------
| Application configuration settings.
| Learn more: https://nylo.dev/docs/7.x/configuration
| -------------------------------------------------------------------------
| You can access these config values throughout your app using:
| `StorageKeysConfig.auth`, `StorageKeysConfig.bearerToken`, etc.
|-------------------------------------------------------------------------- */

final class StorageKeysConfig {
  // Define the keys you want to be synced on boot
  static Future<List<StorageKey>> Function() syncedOnBoot() => () async {
    return [
      auth,
      bearerToken,
      // coins.defaultValue(10), // give the user 10 coins by default
    ];
  };

  static final StorageKey auth = 'SK_USER';

  static final StorageKey bearerToken = 'SK_BEARER_TOKEN';

  static final StorageKey offlineMode = 'BUGHIVE_OFFLINE_MODE';

  static final StorageKey offlineRepositories = 'BUGHIVE_OFFLINE_REPOSITORIES';

  static final StorageKey offlineLogs = 'BUGHIVE_OFFLINE_LOGS';

  static final StorageKey offlineAttachments = 'BUGHIVE_OFFLINE_ATTACHMENTS';

  // static final StorageKey coins = 'SK_COINS';

  /// Add your storage keys here...
}
