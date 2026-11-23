// Criterion 4: the server administration panel calls `GET /v3/admin/whois`
// and `GET`/`PUT /v1/admin/lock|suspend` (Matrix v1.18), and a
// `403 M_FORBIDDEN` shows a translated notice instead of crashing.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/matrix/components/social_admin/matrix_server_admin.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/pages/settings/categories/account/account_state/server_admin_panel.dart';

import '../matrix_room_directory/fakes.dart';

const target = '@bob:example.org';
const encoded = '%40bob%3Aexample.org';
const whoisPath = '/_matrix/client/v3/admin/whois/$target';
const lockPath = '/_matrix/client/v1/admin/lock/$target';
const suspendPath = '/_matrix/client/v1/admin/suspend/$target';

/// A homeserver that knows [target], or refuses everything with [refuse].
class AdminServer {
  bool locked = false;
  bool suspended = true;
  http.Response Function()? refuse;
  http.Response Function()? refusePut;

  http.Response? route(Seen r) {
    if (!r.path.contains('/admin/')) return null;
    final refused =
        refuse?.call() ?? (r.method == 'PUT' ? refusePut?.call() : null);
    if (refused != null) return refused;
    if (r.path == whoisPath) {
      return json({
        'user_id': target,
        'devices': {
          'PHONE': {
            'sessions': [
              {
                'connections': [
                  {'ip': '10.0.0.7', 'last_seen': 1, 'user_agent': 'x'}
                ]
              }
            ]
          }
        }
      });
    }
    final body = r.body as Map?;
    if (r.path == lockPath) {
      if (r.method == 'PUT') locked = body!['locked'] as bool;
      return json({'locked': locked});
    }
    if (r.path == suspendPath) {
      if (r.method == 'PUT') suspended = body!['suspended'] as bool;
      return json({'suspended': suspended});
    }
    return null;
  }
}

void main() {
  setUpAll(prepareTests);

  Future<Script> pumpPanel(WidgetTester tester, AdminServer server) async {
    final script = Script()..routes.add(server.route);
    await tester.pumpWidget(
        host(ServerAdminPanel(MatrixServerAdmin(DirectoryTestClient(script)))));
    return script;
  }

  Future<void> lookUp(WidgetTester tester, String userId) async {
    await tester.enterText(find.byKey(ServerAdminPanel.userFieldKey), userId);
    await tester.tap(find.byKey(ServerAdminPanel.lookUpKey));
    await settle(tester);
  }

  bool switchValue(WidgetTester tester, Key key) =>
      tester.widget<SwitchListTile>(find.byKey(key)).value;

  testWidgets('looks up, then locks and unsuspends with PUT', (tester) async {
    final server = AdminServer();
    final script = await pumpPanel(tester, server);
    await lookUp(tester, target);

    expect(script.seen.map((r) => '${r.method} ${r.url.path}'), [
      'GET /_matrix/client/v3/admin/whois/$encoded',
      'GET /_matrix/client/v1/admin/lock/$encoded',
      'GET /_matrix/client/v1/admin/suspend/$encoded',
    ]);
    expect(find.textContaining('10.0.0.7'), findsOneWidget);
    expect(switchValue(tester, ServerAdminPanel.lockedKey), isFalse);
    expect(switchValue(tester, ServerAdminPanel.suspendedKey), isTrue);

    await tester.tap(find.byKey(ServerAdminPanel.lockedKey));
    await settle(tester);
    await tester.tap(find.byKey(ServerAdminPanel.suspendedKey));
    await settle(tester);

    expect(script.where('PUT', lockPath).map((r) => r.body), [
      {'locked': true}
    ]);
    expect(script.where('PUT', suspendPath).map((r) => r.body), [
      {'suspended': false}
    ]);
    expect(switchValue(tester, ServerAdminPanel.lockedKey), isTrue);
    expect(switchValue(tester, ServerAdminPanel.suspendedKey), isFalse);
    expect(find.byKey(ServerAdminPanel.noticeKey), findsNothing);
  });

  for (final locale in ['en', 'pt']) {
    testWidgets('403 M_FORBIDDEN shows a notice in $locale', (tester) async {
      await tester.runAsync(() => initializeMessages(locale));
      intl.Intl.defaultLocale = locale;
      addTearDown(() => intl.Intl.defaultLocale = null);
      final server = AdminServer()..refuse = () => matrixError('M_FORBIDDEN');
      await pumpPanel(tester, server);
      await lookUp(tester, target);

      expect(tester.takeException(), isNull);
      expect(
          find.text(locale == 'pt'
              ? 'Só quem administra o seu servidor pode fazer isso.'
              : 'Only administrators of your server can do this.'),
          findsOneWidget);
      expect(find.byKey(ServerAdminPanel.lockedKey), findsNothing);
      expect(find.byKey(ServerAdminPanel.suspendedKey), findsNothing);
    });
  }

  testWidgets('a refused PUT keeps the switch and shows the notice',
      (tester) async {
    final server = AdminServer()..refusePut = () => matrixError('M_FORBIDDEN');
    final script = await pumpPanel(tester, server);
    await lookUp(tester, target);
    await tester.tap(find.byKey(ServerAdminPanel.lockedKey));
    await settle(tester);

    expect(script.where('PUT', lockPath), hasLength(1));
    expect(switchValue(tester, ServerAdminPanel.lockedKey), isFalse);
    expect(find.text(ServerAdminPanel.messageServerAdminForbidden),
        findsOneWidget);
  });

  test('a server without the endpoints and an unknown user are told apart',
      () async {
    Future<ServerAdminFailure?> failure(http.Response Function() refuse) async {
      final server = AdminServer()..refuse = refuse;
      final script = Script()..routes.add(server.route);
      final admin = MatrixServerAdmin(DirectoryTestClient(script));
      return (await admin.lookUp(target)).failure;
    }

    expect(await failure(() => matrixError('M_UNRECOGNIZED', status: 404)),
        ServerAdminFailure.unsupported);
    expect(await failure(() => matrixError('M_NOT_FOUND', status: 404)),
        ServerAdminFailure.notFound);
    expect(await failure(() => http.Response('oops', 500)),
        ServerAdminFailure.other);
  });

  testWidgets('a malformed user ID is not sent', (tester) async {
    final script = await pumpPanel(tester, AdminServer());
    await lookUp(tester, 'bob');
    expect(script.seen, isEmpty);
    expect(find.text(ServerAdminPanel.messageServerAdminInvalidUser),
        findsOneWidget);
  });
}
