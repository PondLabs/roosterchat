import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/matrix_security_tab.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/session/matrix_session_view.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../speed_log/fake_account.dart';
import 'matrix_org_auth_metadata.dart';

/// How a homeserver lets the app sign sessions out.
enum SessionsKind {
  /// The Matrix Authentication Service, as matrix.org: the client API
  /// answers 404 `M_UNRECOGNIZED` to `DELETE /devices` and `delete_devices`,
  /// and `/auth_metadata` names the account page.
  accountService,

  /// A server without it: device deletion through the client API, behind
  /// the password (user-interactive authentication).
  legacy,

  /// Neither: no account page and no device deletion.
  neither,
}

const ownDevice = 'GHTYAJCE';
const password = '1234';

/// The days since this device was last seen, by device id.
const sessionAges = {
  ownDevice: Duration.zero,
  'E2ETESTA': Duration(hours: 1),
  'OLDPHONE': Duration(days: 100),
  'OLDWEBXX': Duration(days: 200),
};

/// The SDK's fake homeserver, with the sessions of [sessionAges] and the
/// device routes of a [kind] server. [authMetadata] is what
/// `/auth_metadata` gives back on an [SessionsKind.accountService] server,
/// matrix.org's own by default.
class SessionsServer extends FakeTransport {
  SessionsServer(this.kind, {Map<String, Object?>? authMetadata})
      : authMetadata = authMetadata ??
            (jsonDecode(matrixOrgAuthMetadata) as Map<String, Object?>);

  final SessionsKind kind;
  final Map<String, Object?> authMetadata;

  /// The sessions the account has now, by device id.
  final Map<String, int> devices = {
    for (final MapEntry(:key, :value) in sessionAges.entries)
      key: DateTime.now().subtract(value).millisecondsSinceEpoch,
  };

  /// Every request, as its method and path.
  final List<String> requests = [];

  /// The requests that would sign a session out through the client API.
  Iterable<String> get deletions => requests.where((r) =>
      r.startsWith('DELETE /_matrix/client/v3/devices') ||
      r.startsWith('POST /_matrix/client/v3/delete_devices'));

  /// Signs [deviceId] out, as the account page does when the person ends
  /// that session there.
  void endOnAccountPage(String deviceId) => devices.remove(deviceId);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    requests.add('${request.method} $path');
    const devicesPath = '/_matrix/client/v3/devices';
    if (request.method == 'GET' && path == devicesPath) {
      return _json(request, 200, {
        'devices': [
          for (final MapEntry(:key, :value) in devices.entries)
            {
              'device_id': key,
              'display_name': 'Session $key',
              'last_seen_ts': value,
            },
        ],
      });
    }
    if (request.method == 'GET' && path == '/_matrix/client/v1/auth_metadata') {
      return kind == SessionsKind.accountService
          ? _json(request, 200, authMetadata)
          : _unrecognized(request);
    }
    final deleteOne =
        request.method == 'DELETE' && path.startsWith('$devicesPath/');
    final deleteMany =
        request.method == 'POST' && path == '/_matrix/client/v3/delete_devices';
    if (deleteOne || deleteMany) {
      if (kind != SessionsKind.legacy) return _unrecognized(request);
      final bytes = await request.finalize().toBytes();
      final body = bytes.isEmpty
          ? const <String, Object?>{}
          : jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      final auth = body['auth'] as Map?;
      if (auth?['type'] != 'm.login.password' ||
          auth?['password'] != password) {
        return _json(request, 401, {
          'flows': [
            {
              'stages': ['m.login.password']
            },
          ],
          'params': {},
          'session': 'uia-session',
        });
      }
      final ids = deleteOne
          ? [Uri.decodeComponent(path.substring(devicesPath.length + 1))]
          : (body['devices'] as List).cast<String>();
      ids.forEach(devices.remove);
      return _json(request, 200, {});
    }
    return super.send(request);
  }

  http.StreamedResponse _unrecognized(http.BaseRequest request) => _json(
      request,
      404,
      {'errcode': 'M_UNRECOGNIZED', 'error': 'Unrecognized request'});

  http.StreamedResponse _json(
          http.BaseRequest request, int status, Object body) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          headers: {'content-type': 'application/json'}, request: request);
}

/// The browser: every link the app opens, kept instead of opened.
class FakeBrowser extends UrlLauncherPlatform {
  final List<Uri> opened = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(Uri.parse(url));
    return true;
  }
}

var _accounts = 0;

/// An account signed in on [server], with its sync loop stopped.
Future<MatrixClient> signIn(WidgetTester tester, SessionsServer server) async {
  late MatrixClient client;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
  await tester.runAsync(() async {
    client = await fakeAccount('sessions_${_accounts++}', server);
    final mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.abortSync();
  });
  return client;
}

/// The security settings of [client] as the app shows them, [width] wide.
Future<void> openSessions(WidgetTester tester, MatrixClient client,
    {double width = 1280, double height = 900, Key? boundary}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      navigatorKey: navigator,
      theme: ThemeDark.theme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SingleChildScrollView(child: MatrixSecurityTab(client)),
      ),
    ),
  ));
  await settle(
      tester, () => find.byType(MatrixSessionView).evaluate().isNotEmpty);
  // The answers after the list: what the server allows.
  await settle(tester, () => false, rounds: 5, expectDone: false);
}

/// Lets the account's real work (database, the fake server) run between
/// frames until [done].
Future<void> settle(WidgetTester tester, bool Function() done,
    {int rounds = 100, bool expectDone = true, String? reason}) async {
  for (var i = 0; i < rounds && !done(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (expectDone) expect(done(), isTrue, reason: reason);
}

/// The person leaves the app (for the browser) and comes back to it.
Future<void> leaveAndComeBack(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

/// The session row of [deviceId].
Finder sessionRow(String deviceId) => find.ancestor(
    of: find.text(deviceId), matching: find.byType(MatrixSessionView));

/// The button that removes [deviceId].
Finder removeButton(String deviceId) => find.descendant(
    of: sessionRow(deviceId), matching: find.byIcon(Icons.delete));

/// Scrolls to [button] and taps it.
Future<void> press(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
}

/// The button that signs out every session not used for two months.
Finder get endInactiveButton => find.byIcon(Icons.logout);
