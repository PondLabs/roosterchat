import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/push_notification/android/android_notifier.dart';
import 'package:rooster/client/components/push_notification/linux/linux_notifier.dart';
import 'package:rooster/client/components/push_notification/notifier.dart';
import 'package:rooster/client/components/push_notification/web/web_notifier_stub.dart';
import 'package:rooster/client/components/push_notification/windows/windows_notifier.dart';
import 'package:rooster/client/matrix/components/push_notifications/matrix_push_notification_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/languages.dart';
import 'package:rooster/utils/language/app_language.dart';

import '../matrix_phase0/test_helpers.dart';

/// A notifier that gets its notifications through a push gateway, like
/// Firebase and UnifiedPush on Android.
class FakeGatewayNotifier implements Notifier {
  FakeGatewayNotifier(this.token);
  final String? token;

  @override
  bool get needsToken => true;

  @override
  Future<String?> getToken() async => token;

  @override
  Map<String, dynamic>? extraRegistrationData() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubClient implements MatrixClient {
  _StubClient(this._mx);
  final matrix.Client _mx;

  @override
  String get identifier => 'client-1';

  @override
  matrix.Client getMatrixClient() => _mx;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<http.Request> requests;
  late List<Map<String, Object?>> registered;

  MatrixPushNotificationComponent component(Notifier? notifier) {
    final mx = TestMatrixClient('Rooster test device',
        accessToken: 'token',
        userId: '@alice:example.test', httpClient: MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/_matrix/client/v3/pushers') {
        return http.Response(jsonEncode({'pushers': registered}), 200);
      }
      return http.Response('{}', 200);
    }));
    return MatrixPushNotificationComponent(_StubClient(mx),
        notifier: () => notifier, pushGateway: () => 'push.example.test');
  }

  Iterable<http.Request> pusherSets() =>
      requests.where((r) => r.url.path == '/_matrix/client/v3/pushers/set');

  setUp(() {
    requests = [];
    registered = [];
    AppLanguage.current.value = Languages.english;
  });

  tearDown(() => AppLanguage.current.value = Languages.fallback);

  group('no pusher where nothing is pushed', () {
    final notifiers = <String, Notifier? Function()>{
      'no notifier': () => null,
      'Linux': () => LinuxNotifier(),
      'Windows': () => WindowsNotifier(),
      'browser': () => WebNotifier(),
      'Android background service': () => AndroidNotifier(),
    };
    notifiers.forEach((name, make) {
      test(name, () async {
        registered = [
          {
            'app_id': 'com.pondlabs.rooster.android',
            'pushkey': 'phone-key',
            'app_display_name': 'Rooster',
            'device_display_name': 'Rooster test device',
            'kind': 'http',
            'lang': 'en',
            'data': {'url': 'https://push.example.test/_matrix/push/v1/notify'},
          }
        ];
        final notifier = make();
        expect(MatrixPushNotificationComponent.deliversPush(notifier), isFalse);
        await component(notifier).updatePushers();
        expect(pusherSets(), isEmpty);
        // Not even read: the pushers there belong to other devices.
        expect(requests, isEmpty);
      });
    });
  });

  group('where the gateway delivers push', () {
    for (final language in Languages.supported) {
      test('registers with lang ${language.code}', () async {
        AppLanguage.current.value = language;
        await component(FakeGatewayNotifier('endpoint-key')).updatePushers();

        final set = pusherSets().single;
        final body = jsonDecode(set.body) as Map<String, dynamic>;
        expect(body['lang'], language.code);
        expect(body['pushkey'], 'endpoint-key');
        expect(body['kind'], 'http');
        expect(body['append'], isTrue);
        expect(body['data']['url'],
            'https://push.example.test/_matrix/push/v1/notify');
        expect(body['data']['local_client_id'], 'client-1');
      });
    }

    test('does not register again when nothing changed', () async {
      registered = [
        {
          'app_id': 'com.pondlabs.rooster.android',
          'pushkey': 'endpoint-key',
          'app_display_name': BuildConfig.appName,
          'device_display_name': 'Rooster test device',
          'kind': 'http',
          'lang': 'en',
          'data': {
            'local_client_id': 'client-1',
            'url': 'https://push.example.test/_matrix/push/v1/notify',
            'format': 'event_id_only',
          },
        }
      ];
      await component(FakeGatewayNotifier('endpoint-key')).updatePushers();
      expect(pusherSets(), isEmpty);

      // A new language is a new registration.
      AppLanguage.current.value = Languages.portuguese;
      await component(FakeGatewayNotifier('endpoint-key')).updatePushers();
      expect(jsonDecode(pusherSets().single.body)['lang'], 'pt');
    });

    test('without a token, only this device\'s old pusher goes', () async {
      registered = [
        {
          'app_id': 'com.pondlabs.rooster.android',
          'pushkey': 'old-key',
          'app_display_name': 'Rooster',
          'device_display_name': 'Rooster test device',
          'kind': 'http',
          'lang': 'en',
          'data': {'url': 'https://push.example.test/_matrix/push/v1/notify'},
        }
      ];
      await component(FakeGatewayNotifier(null)).updatePushers();
      final body = jsonDecode(pusherSets().single.body) as Map;
      expect(body['pushkey'], 'old-key');
      expect(body['kind'], isNull);
    });
  });
}
