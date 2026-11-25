import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart' as intl;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/matrix_security_tab.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/session/matrix_session_name_view.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../device_verification/verify_device_layout.dart'
    show loadFontsAndLanguages;
import '../matrix_phase0/test_helpers.dart';

class _StubClient implements MatrixClient {
  _StubClient(this._mx);
  final matrix.Client _mx;

  @override
  matrix.Client getMatrixClient() => _mx;

  @override
  matrix.Client get matrixClient => _mx;

  @override
  Future<bool> hasServerDisabledEncryption() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// How the fake homeserver answers `PUT /devices/{id}`.
enum _Put { ok, serverError, unreachable }

/// A homeserver with two sessions, in memory: it lists them, renames them
/// and says whether an account page manages them.
class _Server {
  _Server({this.accountPage = false});

  final bool accountPage;
  _Put put = _Put.ok;
  final names = <String, String?>{'LAPTOP': 'Old laptop', 'PHONE': 'Phone'};
  final puts = <(String, Object?)>[];
  int listed = 0;

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/_matrix/client/v3/devices') {
      listed++;
      return http.Response(
          jsonEncode({
            'devices': [
              for (final entry in names.entries)
                {
                  'device_id': entry.key,
                  if (entry.value != null) 'display_name': entry.value,
                },
            ],
          }),
          200);
    }
    if (path == '/_matrix/client/v1/auth_metadata') {
      if (!accountPage) {
        return http.Response('{"errcode":"M_UNRECOGNIZED"}', 404);
      }
      return http.Response(
          jsonEncode({
            'issuer': 'https://auth.example.test/',
            'account_management_uri': 'https://auth.example.test/account/',
            'account_management_actions_supported': ['org.matrix.session_end'],
          }),
          200);
    }
    if (request.method == 'DELETE' && path == '/_matrix/client/v3/devices/_') {
      return http.Response('{"errcode":"M_FORBIDDEN"}', 403);
    }
    const prefix = '/_matrix/client/v3/devices/';
    if (request.method == 'PUT' && path.startsWith(prefix)) {
      final id = Uri.decodeComponent(path.substring(prefix.length));
      final body = jsonDecode(request.body) as Map<String, Object?>;
      puts.add((
        id,
        body.containsKey('display_name') ? body['display_name'] : #absent
      ));
      switch (put) {
        case _Put.serverError:
          return http.Response('{"errcode":"M_UNKNOWN","error":"boom"}', 500);
        case _Put.unreachable:
          throw http.ClientException('Connection refused', request.url);
        case _Put.ok:
          names[id] = body['display_name'] as String?;
          return http.Response('{}', 200);
      }
    }
    return http.Response('{}', 200);
  }
}

void main() {
  setUpAll(loadFontsAndLanguages);
  tearDown(() => intl.Intl.defaultLocale = null);

  late _Server server;

  /// Lets the fake homeserver's answers arrive (real time) and draws what
  /// they changed: a few rounds, then until no spinner is left.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
      if (i >= 5 && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpTab(WidgetTester tester, {bool accountPage = false}) async {
    server = _Server(accountPage: accountPage);
    final mx = TestMatrixClient('Rooster test',
        userId: '@alice:example.test',
        accessToken: 'token',
        httpClient: MockClient(server.handle));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: SingleChildScrollView(child: MatrixSecurityTab(_StubClient(mx))),
      ),
    ));
    await settle(tester);
  }

  Finder rename(String deviceId) =>
      find.byKey(ValueKey('rename-session-$deviceId'));

  Future<void> openRename(WidgetTester tester, String deviceId) async {
    await tester.tap(rename(deviceId));
    await tester.pumpAndSettle();
  }

  Future<void> renameTo(
      WidgetTester tester, String deviceId, String name) async {
    await openRename(tester, deviceId);
    await tester.enterText(find.byKey(const ValueKey('session-name')), name);
    await tester.pump();
    await tester.tap(find.text(CommonStrings.promptSave).last);
    await settle(tester);
  }

  testWidgets('lists the sessions with a rename button each', (tester) async {
    await pumpTab(tester);
    expect(find.text('Old laptop'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(rename('LAPTOP'), findsOneWidget);
    expect(rename('PHONE'), findsOneWidget);
  });

  testWidgets('the dialog starts with the current name', (tester) async {
    await pumpTab(tester);
    await openRename(tester, 'LAPTOP');
    expect(find.text(MatrixSessionNameView.labelSessionRenameTitle),
        findsOneWidget);
    final field = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey('session-name')),
        matching: find.byType(EditableText)));
    expect(field.controller.text, 'Old laptop');
  });

  testWidgets('renaming puts the new name and lists it', (tester) async {
    await pumpTab(tester);
    final listedBefore = server.listed;
    await renameTo(tester, 'LAPTOP', '  Work laptop ');
    expect(server.puts, [('LAPTOP', 'Work laptop')]);
    expect(server.listed, listedBefore + 1,
        reason: 'the list is fetched again');
    expect(find.text('Work laptop'), findsOneWidget);
    expect(find.text('Old laptop'), findsNothing);
    expect(find.text(MatrixSessionNameView.messageSessionRenameFailed),
        findsNothing);
  });

  testWidgets('removing the name puts display_name null and lists none',
      (tester) async {
    await pumpTab(tester);
    await openRename(tester, 'PHONE');
    await tester.tap(find.text(MatrixSessionNameView.promptSessionNameRemove));
    await settle(tester);
    expect(server.puts, [('PHONE', null)]);
    expect(server.names['PHONE'], isNull);
    expect(find.text('Phone'), findsNothing);
    expect(find.text('PHONE'), findsOneWidget, reason: 'its id stays');
  });

  testWidgets('a server error keeps the name and says so', (tester) async {
    await pumpTab(tester);
    server.put = _Put.serverError;
    final listedBefore = server.listed;
    await renameTo(tester, 'LAPTOP', 'Work laptop');
    expect(server.puts, [('LAPTOP', 'Work laptop')]);
    expect(server.listed, listedBefore);
    expect(find.text('Old laptop'), findsOneWidget);
    expect(find.text('Work laptop'), findsNothing);
    expect(find.text("The session's name was not changed. Try again."),
        findsOneWidget);
  });

  testWidgets('an unreachable server keeps the name and says so',
      (tester) async {
    await pumpTab(tester);
    server.put = _Put.unreachable;
    await openRename(tester, 'PHONE');
    await tester.tap(find.text(MatrixSessionNameView.promptSessionNameRemove));
    await settle(tester);
    expect(server.puts, [('PHONE', null)]);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text(MatrixSessionNameView.messageSessionRenameFailed),
        findsOneWidget);
  });

  testWidgets('the error is in Portuguese, and a later rename clears it',
      (tester) async {
    intl.Intl.defaultLocale = 'pt';
    await pumpTab(tester);
    server.put = _Put.serverError;
    await renameTo(tester, 'LAPTOP', 'Notebook do trabalho');
    expect(find.text('O nome da sessão não foi alterado. Tente novamente.'),
        findsOneWidget);
    server.put = _Put.ok;
    await renameTo(tester, 'LAPTOP', 'Notebook do trabalho');
    expect(find.text('Notebook do trabalho'), findsOneWidget);
    expect(find.text('O nome da sessão não foi alterado. Tente novamente.'),
        findsNothing);
  });

  testWidgets('cancelling or an empty name sends nothing', (tester) async {
    await pumpTab(tester);
    await openRename(tester, 'LAPTOP');
    await tester.tap(find.text(CommonStrings.promptCancel).last);
    await tester.pumpAndSettle();
    await renameTo(tester, 'LAPTOP', '   ');
    expect(server.puts, isEmpty);
    expect(find.text('Old laptop'), findsOneWidget);
  });

  testWidgets('no rename where the account page manages sessions',
      (tester) async {
    await pumpTab(tester, accountPage: true);
    expect(find.text('Old laptop'), findsOneWidget);
    expect(rename('LAPTOP'), findsNothing);
    expect(rename('PHONE'), findsNothing);
  });
}
