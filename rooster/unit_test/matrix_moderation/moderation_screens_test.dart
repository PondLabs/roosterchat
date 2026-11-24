// The moderation screens: the banned list (criterion 1), the server ACL
// editor that will not save a lockout (criterion 3), the policy server and
// its rules (criterion 4), the reason dialog (criterion 2), and the room
// settings section that only shows what our power level allows.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/moderation/matrix_policy_server.dart';
import 'package:rooster/client/matrix/components/moderation/matrix_room_moderation.dart';
import 'package:rooster/client/matrix/components/moderation/matrix_server_acl.dart';
import 'package:rooster/ui/organisms/moderation/banned_members_view.dart';
import 'package:rooster/ui/organisms/moderation/moderation_reason_dialog.dart';
import 'package:rooster/ui/organisms/moderation/policy_server_view.dart';
import 'package:rooster/ui/organisms/moderation/server_acl_editor.dart';
import 'package:rooster/ui/pages/settings/categories/room/permissions/matrix/room_moderation_section.dart';

import 'fakes.dart';

const membersPath = '/_matrix/client/v3/rooms/$roomId/members';
const unbanPath = '/_matrix/client/v3/rooms/$roomId/unban';
const aclPath = '/_matrix/client/v3/rooms/$roomId/state/m.room.server_acl/';
const policyPath = '/_matrix/client/v3/rooms/$roomId/state/m.room.policy/';

http.Response? oneBanned(Seen r) => r.method == 'GET' && r.path == membersPath
    ? json({
        'chunk': [
          memberEvent('@troll:example.org', 'ban',
              reason: 'spam', displayName: 'Troll'),
        ]
      })
    : null;

http.Response? acceptState(Seen r) =>
    r.method == 'PUT' && r.path.contains('/state/')
        ? json({'event_id': r'$state'})
        : null;

Future<void> confirmReason(WidgetTester tester, String reason) async {
  await tester.pumpAndSettle();
  await tester.enterText(
      find.byKey(ModerationReasonDialog.reasonFieldKey), reason);
  await tester.tap(find.byKey(ModerationReasonDialog.confirmKey));
}

void main() {
  setUpAll(prepareTests);

  group('banned members', () {
    testWidgets('lists them and unbans with the reason typed', (tester) async {
      final (script, room) = moderatedRoom();
      script.routes
        ..add(oneBanned)
        ..add((r) => r.path == unbanPath ? json({}) : null);
      await tester
          .pumpWidget(host(BannedMembersView(MatrixRoomModeration(room))));
      await settle(tester);

      expect(find.text('Troll'), findsOneWidget);
      expect(find.textContaining(BannedMembersView.labelBanReason('spam')),
          findsOneWidget);

      await tester
          .tap(find.byKey(BannedMembersView.unbanKey('@troll:example.org')));
      await confirmReason(tester, 'appeal accepted');
      await settle(tester);

      expect(script.where('POST', unbanPath).single.body,
          {'user_id': '@troll:example.org', 'reason': 'appeal accepted'});
      expect(find.text('Troll'), findsNothing);
      expect(find.text(BannedMembersView.labelNoBannedMembers), findsOneWidget);
    });

    testWidgets('M_FORBIDDEN is said in words and the member stays listed',
        (tester) async {
      final (script, room) = moderatedRoom();
      script.routes
        ..add(oneBanned)
        ..add((r) => r.path == unbanPath ? matrixError('M_FORBIDDEN') : null);
      await tester
          .pumpWidget(host(BannedMembersView(MatrixRoomModeration(room))));
      await settle(tester);

      await tester
          .tap(find.byKey(BannedMembersView.unbanKey('@troll:example.org')));
      await confirmReason(tester, '');
      await settle(tester);

      expect(script.where('POST', unbanPath).single.body,
          {'user_id': '@troll:example.org'});
      expect(find.text(ModerationStrings.errorModerationForbidden),
          findsOneWidget);
      expect(find.text('Troll'), findsOneWidget);
    });

    testWidgets('cancelling the dialog sends nothing', (tester) async {
      final (script, room) = moderatedRoom();
      script.routes.add(oneBanned);
      await tester
          .pumpWidget(host(BannedMembersView(MatrixRoomModeration(room))));
      await settle(tester);

      await tester
          .tap(find.byKey(BannedMembersView.unbanKey('@troll:example.org')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(writes(script), isEmpty);
      expect(find.text('Troll'), findsOneWidget);
    });
  });

  group('server ACL editor', () {
    Future<Script> open(WidgetTester tester) async {
      final (script, room) = moderatedRoom();
      script.routes.add(acceptState);
      await tester.pumpWidget(host(ServerAclEditor(MatrixServerAcl(room))));
      await tester.pumpAndSettle();
      return script;
    }

    bool saveEnabled(WidgetTester tester) => tester
        .widget<ElevatedButton>(find.descendant(
            of: find.byKey(ServerAclEditor.saveKey),
            matching: find.byType(ElevatedButton)))
        .enabled;

    testWidgets('an empty allow list is refused, said why, and never sent',
        (tester) async {
      final script = await open(tester);

      await tester.enterText(find.byKey(ServerAclEditor.allowFieldKey), '');
      await tester.pumpAndSettle();

      expect(
          find.text(ServerAclEditor.errorServerAclAllowEmpty), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      await tester.tap(find.byKey(ServerAclEditor.saveKey));
      await settle(tester);
      expect(writes(script), isEmpty);
    });

    testWidgets('denying our own server is refused', (tester) async {
      final script = await open(tester);

      await tester.enterText(
          find.byKey(ServerAclEditor.denyFieldKey), 'evil.example\n*.org');
      await tester.pumpAndSettle();

      expect(
          find.text(
              ServerAclEditor.errorServerAclOwnServerDenied('example.org')),
          findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      expect(writes(script), isEmpty);
    });

    testWidgets('a safe ACL is saved with its three fields', (tester) async {
      final script = await open(tester);

      await tester.enterText(find.byKey(ServerAclEditor.allowFieldKey),
          '*.example.org\nexample.org');
      await tester.enterText(
          find.byKey(ServerAclEditor.denyFieldKey), ' evil.example \n\n');
      await tester.tap(find.byKey(ServerAclEditor.ipLiteralsKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ServerAclEditor.saveKey));
      await settle(tester);

      expect(script.where('PUT', aclPath).single.body, {
        'allow': ['*.example.org', 'example.org'],
        'deny': ['evil.example'],
        'allow_ip_literals': false,
      });
      expect(find.text(ServerAclEditor.messageServerAclSaved), findsOneWidget);
    });
  });

  group('policy server', () {
    testWidgets('shows the setting and the rules, and saves via and key',
        (tester) async {
      final (script, room) = moderatedRoom();
      script.routes.add(acceptState);
      putState(room, 'm.room.policy', {
        'via': 'old.example.org',
        'public_keys': {'ed25519': 'oldkey'},
      });
      putState(room, 'm.policy.rule.user',
          {'entity': '@spammer:*', 'recommendation': 'm.ban', 'reason': 'spam'},
          stateKey: 'r1');
      putState(room, 'm.policy.rule.server', {'entity': 42}, stateKey: 'bad');

      await tester.pumpWidget(host(PolicyServerView(MatrixPolicyServer(room))));
      await tester.pumpAndSettle();

      expect(find.text('old.example.org'), findsOneWidget);
      expect(find.text('@spammer:*'), findsOneWidget);
      expect(
          find.text([
            PolicyServerView.labelPolicyRuleUser,
            PolicyServerView.labelPolicyRuleBan,
            'spam'
          ].join(' · ')),
          findsOneWidget);

      await tester.enterText(
          find.byKey(PolicyServerView.viaFieldKey), 'policy.example.org');
      await tester.enterText(
          find.byKey(PolicyServerView.keyFieldKey), 'newkey');
      await tester.tap(find.byKey(PolicyServerView.saveKey));
      await settle(tester);

      expect(script.where('PUT', policyPath).single.body, {
        'via': 'policy.example.org',
        'public_keys': {'ed25519': 'newkey'},
      });
    });

    testWidgets('a key-less policy server is refused and said why',
        (tester) async {
      final (script, room) = moderatedRoom();
      script.routes.add(acceptState);
      await tester.pumpWidget(host(PolicyServerView(MatrixPolicyServer(room))));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(PolicyServerView.viaFieldKey), 'policy.example.org');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PolicyServerView.saveKey));
      await settle(tester);

      expect(find.text(PolicyServerView.errorPolicyServerKey), findsOneWidget);
      expect(writes(script), isEmpty);
      expect(find.text(PolicyServerView.labelNoPolicyRules), findsOneWidget);
    });
  });

  group('room settings section', () {
    testWidgets('a moderator sees the three screens', (tester) async {
      final (_, room) = moderatedRoom(ownLevel: 100);
      await tester.pumpWidget(host(RoomModerationSection(room)));

      expect(find.byKey(RoomModerationSection.bannedKey), findsOneWidget);
      expect(find.byKey(RoomModerationSection.serverAclKey), findsOneWidget);
      expect(find.byKey(RoomModerationSection.policyServerKey), findsOneWidget);
    });

    testWidgets('a member without power sees none of them', (tester) async {
      final (_, room) = moderatedRoom(ownLevel: 0);
      await tester.pumpWidget(host(RoomModerationSection(room)));

      expect(
          find.text(RoomModerationSection.labelRoomModeration), findsNothing);
      expect(find.byKey(RoomModerationSection.bannedKey), findsNothing);
      expect(find.byKey(RoomModerationSection.serverAclKey), findsNothing);
      expect(find.byKey(RoomModerationSection.policyServerKey), findsNothing);
    });

    testWidgets('each screen follows its own power level', (tester) async {
      final (_, room) = moderatedRoom();
      putState(room, matrix.EventTypes.RoomPowerLevels, {
        'users': {self: 50},
        'ban': 50,
        'state_default': 50,
        'events': {'m.room.server_acl': 100, 'm.room.policy': 100},
      });
      await tester.pumpWidget(host(RoomModerationSection(room)));

      expect(find.byKey(RoomModerationSection.bannedKey), findsOneWidget);
      expect(find.byKey(RoomModerationSection.serverAclKey), findsNothing);
      expect(find.byKey(RoomModerationSection.policyServerKey), findsNothing);
    });

    testWidgets('the banned list needs the ban level', (tester) async {
      final (_, room) = moderatedRoom();
      putState(room, matrix.EventTypes.RoomPowerLevels, {
        'users': {self: 50},
        'ban': 100,
        'state_default': 50,
      });
      await tester.pumpWidget(host(RoomModerationSection(room)));

      expect(find.byKey(RoomModerationSection.bannedKey), findsNothing);
      expect(find.byKey(RoomModerationSection.serverAclKey), findsOneWidget);
      expect(find.byKey(RoomModerationSection.policyServerKey), findsOneWidget);
    });

    testWidgets('opens the banned list', (tester) async {
      final (script, room) = moderatedRoom();
      script.routes.add(oneBanned);
      await tester.pumpWidget(host(RoomModerationSection(room)));

      await tester.tap(find.byKey(RoomModerationSection.bannedKey));
      await settle(tester);

      expect(find.text('Troll'), findsOneWidget);
    });
  });

  group('reason dialog', () {
    testWidgets('gives the trimmed reason, null for blank, nothing on cancel',
        (tester) async {
      late BuildContext context;
      await tester.pumpWidget(host(Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }), scroll: false));

      Future<ModerationReason?> ask() => ModerationReasonDialog.ask(context,
          title: 'Kick', prompt: 'Kick them?', confirmText: 'Kick');

      var answer = ask();
      await confirmReason(tester, '  rude  ');
      expect((await answer)?.reason, 'rude');

      answer = ask();
      await confirmReason(tester, '   ');
      final blank = await answer;
      expect(blank, isNotNull);
      expect(blank!.reason, isNull);

      answer = ask();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await answer, isNull);
    });
  });
}
