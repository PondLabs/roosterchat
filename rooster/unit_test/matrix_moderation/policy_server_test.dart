// Criterion 4: `m.room.policy` (`via`, Matrix v1.18 MSC4284) is read and
// written, and `m.policy.rule.*` rules are read with their `entity`,
// `recommendation` and `reason`, malformed ones skipped without a crash.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/moderation/matrix_policy_server.dart';

import 'fakes.dart';

const policyPath = '/_matrix/client/v3/rooms/$roomId/state/m.room.policy/';

void main() {
  late Script script;
  late matrix.Room room;
  late MatrixPolicyServer policy;

  setUp(() {
    (script, room) = moderatedRoom();
    script.routes.add((r) => r.method == 'PUT' && r.path == policyPath
        ? json({'event_id': r'$policy'})
        : null);
    policy = MatrixPolicyServer(room);
  });

  group('m.room.policy', () {
    test('reads via and the ed25519 key', () {
      expect(policy.current.via, isNull);
      putState(room, 'm.room.policy', {
        'via': 'policy.example.org',
        'public_keys': {'ed25519': 'abc'},
      });
      expect(policy.current.via, 'policy.example.org');
      expect(policy.current.ed25519PublicKey, 'abc');
    });

    test('writes via and the key, keeping fields it does not edit', () async {
      putState(room, 'm.room.policy', {
        'via': 'old.example.org',
        'public_keys': {'ed25519': 'old', 'other': 'kept'},
        'com.example.note': 'kept',
      });

      await policy.save(via: ' policy.example.org ', publicKey: ' new ');

      expect(script.where('PUT', policyPath).single.body, {
        'com.example.note': 'kept',
        'via': 'policy.example.org',
        'public_keys': {'ed25519': 'new', 'other': 'kept'},
      });
    });

    test('a blank via turns the policy server off', () async {
      await policy.save(via: '  ');
      expect(script.where('PUT', policyPath).single.body, isEmpty);
    });

    test('refuses a bad server name or a missing key, sending nothing',
        () async {
      for (final (via, key, problem) in [
        ('not a server', 'k', PolicyServerProblem.invalidServerName),
        (
          'https://policy.example.org',
          'k',
          PolicyServerProblem.invalidServerName
        ),
        ('policy.example.org', ' ', PolicyServerProblem.missingKey),
      ]) {
        await expectLater(
            policy.save(via: via, publicKey: key),
            throwsA(isA<PolicyServerRejected>()
                .having((e) => e.problems, 'problems', [problem])));
      }
      expect(writes(script), isEmpty);
      expect(policy.problemsOf('policy.example.org:8448', 'k'), isEmpty);
    });
  });

  group('m.policy.rule.*', () {
    test('reads entity, recommendation and reason of each kind', () {
      putState(
          room,
          'm.policy.rule.user',
          {
            'entity': '@spammer:*',
            'recommendation': 'm.ban',
            'reason': 'spam',
          },
          stateKey: 'rule1');
      putState(room, 'm.policy.rule.room',
          {'entity': '!bad:example.org', 'recommendation': 'm.ban'},
          stateKey: 'rule2');
      putState(
          room,
          'm.policy.rule.server',
          {
            'entity': '*.evil.example',
            'recommendation': 'org.example.mute',
            'reason': 'abuse',
          },
          stateKey: 'rule3');

      final rules = PolicyRule.of(room);
      expect(rules.map((r) => (r.kind, r.entity, r.recommendation, r.reason)), [
        (PolicyRuleKind.user, '@spammer:*', 'm.ban', 'spam'),
        (PolicyRuleKind.room, '!bad:example.org', 'm.ban', null),
        (PolicyRuleKind.server, '*.evil.example', 'org.example.mute', 'abuse'),
      ]);
      expect(rules.first.isBan, isTrue);
      expect(rules.last.isBan, isFalse);
    });

    test('skips malformed and removed rules without a crash', () {
      final malformed = <Map<String, Object?>>[
        {},
        {'entity': '@a:b'},
        {'recommendation': 'm.ban'},
        {'entity': '', 'recommendation': 'm.ban'},
        {'entity': 42, 'recommendation': 'm.ban'},
        {'entity': '@a:b', 'recommendation': 7},
        {
          'entity': ['@a:b'],
          'recommendation': 'm.ban'
        },
      ];
      for (final (i, content) in malformed.indexed) {
        putState(room, 'm.policy.rule.user', content, stateKey: 'bad$i');
      }
      putState(room, 'm.policy.rule.user',
          {'entity': '@ok:example.org', 'recommendation': 'm.ban', 'reason': 5},
          stateKey: 'good');

      final rules = PolicyRule.of(room);
      expect(rules.map((r) => r.entity), ['@ok:example.org']);
      expect(rules.single.reason, isNull);
    });

    test('reads the older rule types, counting a rule once', () {
      putState(room, 'm.room.rule.user',
          {'entity': '@old:example.org', 'recommendation': 'm.ban'},
          stateKey: 'a');
      putState(room, 'org.matrix.mjolnir.rule.server',
          {'entity': 'bad.example', 'recommendation': 'm.ban'},
          stateKey: 'b');
      putState(room, 'org.matrix.mjolnir.rule.user',
          {'entity': '@old:example.org', 'recommendation': 'm.ban'},
          stateKey: 'c');

      expect(PolicyRule.of(room).map((r) => (r.kind, r.entity)), [
        (PolicyRuleKind.user, '@old:example.org'),
        (PolicyRuleKind.server, 'bad.example'),
      ]);
    });
  });
}
