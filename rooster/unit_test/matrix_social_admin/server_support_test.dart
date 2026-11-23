// Criterion 2: the account settings show the contacts and help page of
// `/.well-known/matrix/support` (Matrix v1.10), and silently show nothing for
// a 404, broken JSON or an unsafe link.
@TestOn('vm')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/matrix/components/social_admin/matrix_server_support.dart';
import 'package:rooster/ui/pages/settings/categories/account/account_state/server_support_view.dart';

import '../matrix_room_directory/fakes.dart';

const supportUrl = 'https://example.org/.well-known/matrix/support';

/// The support file the fake server answers, and the headers it was asked
/// with.
class SupportScript extends Script {
  SupportScript(this.answerWith);
  final http.Response Function() answerWith;
  final headers = <Map<String, String>>[];

  @override
  Future<http.Response?> answer(http.BaseRequest request) async {
    await super.answer(request);
    if (request.url.toString() != supportUrl) return null;
    headers.add(request.headers);
    return answerWith();
  }
}

Future<(ServerSupportInfo?, SupportScript)> fetch(
    http.Response Function() answer) async {
  final script = SupportScript(answer);
  final info = await MatrixServerSupport.fetch(DirectoryTestClient(script));
  return (info, script);
}

final validFile = {
  'contacts': [
    {
      'matrix_id': '@admin:example.org',
      'email_address': 'admin@example.org',
      'role': 'm.role.admin'
    },
    {'email_address': 'security@example.org', 'role': 'm.role.security'},
    {'matrix_id': '@billing:example.org', 'role': 'org.example.billing'},
  ],
  'support_page': 'https://example.org/help',
};

void main() {
  setUpAll(prepareTests);

  test('reads the server name\'s file, without the access token', () async {
    final (info, script) = await fetch(() => json(validFile));
    expect(script.seen.single.url.toString(), supportUrl);
    expect(script.headers.single.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')));
    expect(info!.supportPage, Uri.parse('https://example.org/help'));
    expect(info.contacts.map((c) => (c.role, c.matrixId, c.email)), [
      ('m.role.admin', '@admin:example.org', 'admin@example.org'),
      ('m.role.security', null, 'security@example.org'),
      ('org.example.billing', '@billing:example.org', null),
    ]);
    expect(
        info.contacts.first.emailLink, Uri.parse('mailto:admin@example.org'));
  });

  for (final (what, answer) in [
    ('a 404, whatever its body', () => json(validFile, status: 404)),
    ('broken JSON', () => http.Response('{"contacts": [', 200)),
    ('an HTML page', () => http.Response('<html>support</html>', 200)),
    ('a JSON list', () => json([validFile])),
    (
      'nothing valid in it',
      () => json({'contacts': 'admin', 'support_page': 7})
    ),
  ]) {
    test('$what gives nothing', () async {
      expect((await fetch(answer)).$1, isNull);
    });
  }

  test('leaves out unsafe links and malformed contacts', () {
    final info = MatrixServerSupport.parse({
      'contacts': [
        {'email_address': 'javascript:alert(1)', 'role': 'm.role.admin'},
        {'matrix_id': 'javascript:alert(1)', 'role': 'm.role.admin'},
        {'email_address': 'a@b.org?body=x', 'role': 'm.role.admin'},
        {'email_address': 'ok@example.org'},
        {'email_address': 'ok@example.org', 'role': 3},
        'admin@example.org',
        {'email_address': 'kept@example.org', 'role': 'm.role.admin'},
      ],
      'support_page': 'javascript:alert(document.cookie)',
    });
    expect(info!.supportPage, isNull);
    expect(info.contacts.map((c) => c.email), ['kept@example.org']);

    for (final page in [
      'http://example.org/help',
      'JaVaScRiPt:alert(1)',
      'data:text/html,hi',
      'https:///nohost',
      'file:///etc/passwd',
    ]) {
      expect(MatrixServerSupport.safePage(page), isNull, reason: page);
    }
    expect(MatrixServerSupport.parse({'support_page': 'javascript:x'}), isNull);
  });

  testWidgets('shows the contacts and opens only safe links', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(host(ServerSupportView(
      () async => MatrixServerSupport.parse(validFile),
      openLink: (_, link) => opened.add(link),
    )));
    await settle(tester);

    expect(
        find.text(ServerSupportView.labelServerSupportAdmin), findsOneWidget);
    expect(find.text(ServerSupportView.labelServerSupportSecurity),
        findsOneWidget);
    expect(find.text('org.example.billing'), findsOneWidget);
    expect(find.text('@admin:example.org'), findsOneWidget);

    await tester
        .tap(find.byKey(ServerSupportView.emailKey('security@example.org')));
    await tester.tap(find.byKey(ServerSupportView.pageKey));
    expect(opened, [
      Uri.parse('mailto:security@example.org'),
      Uri.parse('https://example.org/help'),
    ]);
  });

  testWidgets('shows nothing when the server has nothing', (tester) async {
    await tester.pumpWidget(host(ServerSupportView(() async => null)));
    await settle(tester);
    expect(find.text(ServerSupportView.labelServerSupportHeader), findsNothing);

    await tester.pumpWidget(host(ServerSupportView(
        key: const ValueKey('again'),
        () async => MatrixServerSupport.parse({
              'contacts': [
                {'email_address': 'admin@example.org', 'role': 'm.role.admin'}
              ],
              'support_page': 'javascript:alert(1)'
            }))));
    await settle(tester);
    expect(
        find.text(ServerSupportView.labelServerSupportHeader), findsOneWidget);
    expect(find.byKey(ServerSupportView.pageKey), findsNothing);
  });
}
