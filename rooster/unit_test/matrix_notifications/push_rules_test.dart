import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/push_notifications/matrix_push_rules.dart';

import '../matrix_phase0/test_helpers.dart';

Map<String, Object?> rule(String id,
        {bool enabled = true, bool isDefault = true, String? pattern}) =>
    {
      'rule_id': id,
      'default': isDefault,
      'enabled': enabled,
      'actions': ['notify'],
      if (pattern != null) 'pattern': pattern,
    };

Map<String, Object?> globalRuleset() => {
      'global': {
        'override': [
          rule('.m.rule.master', enabled: false),
          rule('.m.rule.invite_for_me'),
        ],
        'content': [
          rule('.m.rule.contains_user_name', pattern: 'alice'),
          rule('rooster', isDefault: false, pattern: 'rooster'),
        ],
        'underride': [
          rule('.m.rule.call'),
          rule('.m.rule.encrypted_room_one_to_one'),
          rule('.m.rule.room_one_to_one'),
          rule('.m.rule.message'),
          rule('.m.rule.encrypted'),
        ],
        'room': [],
        'sender': [],
      },
    };

/// A homeserver answering the push rules API, refusing writes with
/// [failWith] while it is set.
class FakePushRulesServer {
  final requests = <http.Request>[];
  http.Response? failWith;

  late final client = TestMatrixClient(
    'push_rules_test',
    accessToken: 'token',
    userId: '@alice:example.test',
    httpClient: MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET' &&
          request.url.path == '/_matrix/client/v3/pushrules/') {
        return http.Response(jsonEncode(globalRuleset()), 200);
      }
      if (failWith != null) return failWith!;
      return http.Response('{}', 200);
    }),
  );

  List<http.Request> get writes =>
      requests.where((r) => r.method != 'GET').toList();
}

http.Response matrixError(int status, String errcode,
        {Map<String, String> headers = const {}}) =>
    http.Response(jsonEncode({'errcode': errcode, 'error': 'refused'}), status,
        headers: headers);

void main() {
  late FakePushRulesServer server;
  late MatrixPushRulesController controller;

  setUp(() async {
    server = FakePushRulesServer();
    controller = MatrixPushRulesController(server.client);
    await controller.load();
  });

  test('reads the global ruleset', () {
    expect(server.requests.first.url.path, '/_matrix/client/v3/pushrules/');
    expect(controller.loaded, isTrue);
    expect(controller.isEnabled(GlobalPushRule.master), isFalse);
    for (final rule in GlobalPushRule.values.skip(1)) {
      expect(controller.isEnabled(rule), isTrue, reason: rule.ruleId);
    }
    // Only the keywords you added, not the server's own content rules.
    expect(controller.keywords.map((r) => r.pattern), ['rooster']);
  });

  test('a rule the homeserver does not have is left out', () async {
    final requests = <http.Request>[];
    final c = MatrixPushRulesController(TestMatrixClient('old',
        accessToken: 't', httpClient: MockClient((r) async {
      requests.add(r);
      return http.Response(
          jsonEncode({
            'global': {
              'underride': [rule('.m.rule.message')]
            }
          }),
          200);
    })));
    await c.load();
    expect(c.isEnabled(GlobalPushRule.encryptedDirectMessages), isNull);
    expect(await c.setEnabled(GlobalPushRule.encryptedDirectMessages, false),
        isFalse);
    expect(requests, hasLength(1));
  });

  test('turns default rules off and on', () async {
    expect(await controller.setEnabled(GlobalPushRule.roomMessages, false),
        isTrue);
    expect(controller.isEnabled(GlobalPushRule.roomMessages), isFalse);
    expect(await controller.setEnabled(GlobalPushRule.master, true), isTrue);
    expect(controller.isEnabled(GlobalPushRule.master), isTrue);

    final writes = server.writes;
    expect(writes.map((r) => '${r.method} ${r.url.path}'), [
      'PUT /_matrix/client/v3/pushrules/global/underride/.m.rule.message/enabled',
      'PUT /_matrix/client/v3/pushrules/global/override/.m.rule.master/enabled',
    ]);
    expect(jsonDecode(writes[0].body), {'enabled': false});
    expect(jsonDecode(writes[1].body), {'enabled': true});
  });

  test('adds a keyword as a content rule', () async {
    expect(await controller.addKeyword('  pizza  '), KeywordChange.added);
    expect(controller.keywords.map((r) => r.pattern), ['rooster', 'pizza']);
    final put = server.writes.single;
    expect(put.method, 'PUT');
    expect(put.url.path, '/_matrix/client/v3/pushrules/global/content/pizza');
    final body = jsonDecode(put.body) as Map;
    expect(body['pattern'], 'pizza');
    expect(body['actions'], contains('notify'));
  });

  test('a keyword that is not a valid rule id gets one', () async {
    expect(await controller.addKeyword('.net/core'), KeywordChange.added);
    expect(server.writes.single.url.pathSegments.last, '_.net_core');
  });

  test('rejects an empty or duplicate keyword without a request', () async {
    expect(await controller.addKeyword(''), KeywordChange.empty);
    expect(await controller.addKeyword('   '), KeywordChange.empty);
    expect(await controller.addKeyword('rooster'), KeywordChange.duplicate);
    expect(await controller.addKeyword('ROOSTER '), KeywordChange.duplicate);
    expect(server.writes, isEmpty);
    expect(controller.keywords, hasLength(1));
  });

  test('removes a keyword', () async {
    expect(await controller.removeKeyword('rooster'), isTrue);
    expect(controller.keywords, isEmpty);
    final delete = server.writes.single;
    expect(delete.method, 'DELETE');
    expect(
        delete.url.path, '/_matrix/client/v3/pushrules/global/content/rooster');
    // The server's own rules are not keywords to remove.
    expect(
        await controller.removeKeyword('.m.rule.contains_user_name'), isFalse);
    expect(server.writes, hasLength(1));
  });

  group('an HTTP error puts the state back', () {
    test('when turning a rule off', () async {
      server.failWith = matrixError(403, 'M_FORBIDDEN');
      var notified = 0;
      controller.addListener(() => notified++);

      expect(await controller.setEnabled(GlobalPushRule.directMessages, false),
          isFalse);
      expect(controller.isEnabled(GlobalPushRule.directMessages), isTrue);
      expect(controller.lastError, isA<matrix.MatrixException>());
      expect((controller.lastError as matrix.MatrixException).error,
          matrix.MatrixError.M_FORBIDDEN);
      expect(controller.isPending('.m.rule.room_one_to_one'), isFalse);
      expect(notified, 2);
    });

    test('when adding a keyword, keeping how long to wait', () async {
      server.failWith =
          matrixError(429, 'M_LIMIT_EXCEEDED', headers: {'retry-after': '7'});
      expect(await controller.addKeyword('pizza'), KeywordChange.failed);
      expect(controller.keywords.map((r) => r.pattern), ['rooster']);
      expect(controller.retryAfter, const Duration(seconds: 7));
    });

    test('when removing a keyword', () async {
      server.failWith = matrixError(500, 'M_UNKNOWN');
      expect(await controller.removeKeyword('rooster'), isFalse);
      expect(controller.keywords.map((r) => r.pattern), ['rooster']);
      expect(controller.retryAfter, isNull);
    });

    test('and the next change clears the error', () async {
      server.failWith = matrixError(500, 'M_UNKNOWN');
      await controller.setEnabled(GlobalPushRule.calls, false);
      server.failWith = null;
      expect(await controller.setEnabled(GlobalPushRule.calls, false), isTrue);
      expect(controller.lastError, isNull);
      expect(controller.isEnabled(GlobalPushRule.calls), isFalse);
    });
  });

  test('a ruleset that cannot be read is an error, not empty rules', () async {
    final c = MatrixPushRulesController(TestMatrixClient('down',
        accessToken: 't',
        httpClient: MockClient((r) async => matrixError(502, 'M_UNKNOWN'))));
    await c.load();
    expect(c.loaded, isFalse);
    expect(c.lastError, isNotNull);
    expect(await c.addKeyword('pizza'), KeywordChange.failed);
  });
}
