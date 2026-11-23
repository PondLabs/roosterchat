import 'package:collection/collection.dart';
import 'package:rooster/client/components/push_notification/notification_manager.dart';
import 'package:rooster/client/components/push_notification/notifier.dart';
import 'package:rooster/client/components/push_notification/push_notification_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/languages.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:matrix/matrix.dart';
import 'package:rooster/utils/language/app_language.dart';

class MatrixPushNotificationComponent
    implements PushNotificationComponent<MatrixClient> {
  @override
  MatrixClient client;

  /// The notifier, push gateway and language come from the app unless a
  /// test gives its own.
  MatrixPushNotificationComponent(this.client,
      {Notifier? Function()? notifier,
      String Function()? pushGateway,
      Language Function()? language})
      : _notifier = notifier ?? (() => NotificationManager.notifier),
        _pushGateway = pushGateway ?? (() => preferences.pushGateway),
        _language = language ?? (() => AppLanguage.current.value);

  final Notifier? Function() _notifier;
  final String Function() _pushGateway;
  final Language Function() _language;

  /// Whether [notifier] gets its notifications through a push gateway:
  /// Firebase and UnifiedPush on Android. The desktop and browser notifiers
  /// show what the running app syncs and have no gateway to register, so a
  /// pusher for them would only make the homeserver push to nowhere.
  static bool deliversPush(Notifier? notifier) => notifier?.needsToken == true;

  @override
  Future<void> ensurePushNotificationsRegistered(
      String pushKey, Uri pushServer, String deviceName,
      {Map<String, dynamic>? extraData}) async {
    var matrixClient = client.getMatrixClient();

    Log.i("Current push key: $pushKey");

    var pushers = await matrixClient.getPushers();

    var pusher = Pusher(
        appId: "com.pondlabs.rooster.android",
        pushkey: pushKey,
        appDisplayName: BuildConfig.appName,
        data: PusherData(
          format: "event_id_only",
          url: pushServer,
          additionalProperties: extraData ?? {},
        ),
        deviceDisplayName: deviceName,
        kind: "http",
        // The language the app is shown in, for the gateway's own text.
        lang: _language().code);

    // Registered already, with the same gateway, data and language.
    final wanted = pusher.toJson();
    if (pushers != null &&
        pushers.any((element) =>
            const DeepCollectionEquality().equals(element.toJson(), wanted))) {
      return;
    }

    await matrixClient.postPusher(pusher, append: true);
  }

  Future<void> cleanOldPushers(
      String? currentPushKey, String deviceName, Uri pushGateway) async {
    var matrixClient = client.getMatrixClient();
    var pushers = await matrixClient.getPushers();

    // Check for stale pushers
    if (pushers != null) {
      for (var pusher in pushers) {
        if (pusher.deviceDisplayName == deviceName &&
            (pusher.pushkey != currentPushKey ||
                pusher.data.url != pushGateway)) {
          await matrixClient.deletePusher(pusher);
        }
      }
    }
  }

  @override
  Future<void> updatePushers() async {
    if (NotificationManager.notifierLoading != null) {
      await NotificationManager.notifierLoading;
    }
    var notifier = _notifier();
    // Nothing to register where nothing is pushed, and nothing to clean:
    // the pushers of this account's phones are theirs.
    if (!deliversPush(notifier)) return;

    var key = await notifier!.getToken();
    var mxClient = client.getMatrixClient();
    var extraData = notifier.extraRegistrationData();

    extraData ??= {};

    extraData["local_client_id"] = client.identifier;

    var name = mxClient.clientName;

    final gateway = _pushGateway();
    var uri = Uri.parse(gateway);
    if (uri.hasScheme == false) {
      uri = Uri.https(gateway);
    }

    uri = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.port,
        path: "/_matrix/push/v1/notify");

    await cleanOldPushers(key, name, uri);

    if (key == null) {
      return;
    }

    await ensurePushNotificationsRegistered(key, uri, name,
        extraData: extraData);
  }

  @override
  void postLoginInit() async {
    updatePushers();
  }
}
