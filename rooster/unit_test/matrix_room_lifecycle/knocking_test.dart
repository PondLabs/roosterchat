// Criterion 3: someone outside a `knock` or `knock_restricted` room asks
// to join with knockRoom (and an optional reason); a moderator lets them in
// (invite) or declines (kick with a reason); someone without the power sees
// no moderation actions.
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/knocking/matrix_knocking_component.dart';
import 'package:rooster/ui/organisms/chat/knock_request_banner.dart';
import 'package:rooster/ui/pages/settings/categories/room/security/matrix_room_knock_requests.dart';

import 'fakes.dart';

const knocker = '@knocker:elsewhere.example';

StateSpec joinRule(String rule) =>
    state(matrix.EventTypes.RoomJoinRules, {'join_rule': rule});

StateSpec knockFrom(String userId, {String? reason, String? displayName}) =>
    state(
      matrix.EventTypes.RoomMember,
      {
        'membership': 'knock',
        if (reason != null) 'reason': reason,
        if (displayName != null) 'displayname': displayName,
      },
      stateKey: userId,
      sender: userId,
    );

void main() {
  setUpAll(preparePreferences);

  group('asking to join', () {
    for (final rule in ['knock', 'knock_restricted']) {
      test('$rule: a non-member knocks with a reason', () async {
        final server = FakeHomeserver();
        final room = buildRoom(LifecycleTestClient(server),
            membership: matrix.Membership.leave, states: [joinRule(rule)]);
        final knocking = MatrixKnockingComponent(room);

        expect(knocking.roomAcceptsKnocks, isTrue);
        expect(knocking.canKnock, isTrue);
        await knocking.knock(reason: '  Friend of Ana  ');

        final knock = server.where('POST', '/v3/knock/').single;
        expect(knock.path, '/_matrix/client/v3/knock/!room:example.org');
        expect(knock.body, {'reason': 'Friend of Ana'});
      });
    }

    test('without a reason, the body has none', () async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server),
          membership: matrix.Membership.leave, states: [joinRule('knock')]);

      await MatrixKnockingComponent(room).knock(reason: '');

      expect(server.where('POST', '/knock/').single.body, <String, Object?>{});
    });

    test('rooms that take no knocks, and members, cannot knock', () {
      final client = LifecycleTestClient(FakeHomeserver());
      for (final rule in ['public', 'invite', 'restricted']) {
        final room = buildRoom(client,
            membership: matrix.Membership.leave, states: [joinRule(rule)]);
        expect(MatrixKnockingComponent(room).canKnock, isFalse, reason: rule);
      }
      for (final membership in [
        matrix.Membership.join,
        matrix.Membership.invite,
        matrix.Membership.ban,
        matrix.Membership.knock,
      ]) {
        final room = buildRoom(client,
            membership: membership, states: [joinRule('knock')]);
        expect(MatrixKnockingComponent(room).canKnock, isFalse,
            reason: membership.name);
      }
    });

    testWidgets('the banner sends the request with its note, then waits',
        (tester) async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server),
          membership: matrix.Membership.leave,
          states: [joinRule('knock_restricted')]);

      await tester.pumpWidget(host(KnockRequestBanner(room: room)));
      expect(
          find.text(KnockRequestBanner.messageRoomTakesKnocks), findsOneWidget);

      await tester.tap(find.text(KnockRequestBanner.promptRequestToJoin));
      await settle(tester);
      await answerPrompt(tester, 'Ana invited me',
          submit: KnockRequestBanner.promptSendKnock);

      expect(server.where('POST', '/knock/!room:example.org').single.body,
          {'reason': 'Ana invited me'});
      expect(find.text(KnockRequestBanner.messageKnockPending), findsOneWidget);
      expect(find.text(KnockRequestBanner.promptRequestToJoin), findsNothing);
    });

    testWidgets('no banner for members or rooms without knocking',
        (tester) async {
      final client = LifecycleTestClient(FakeHomeserver());
      final member = buildRoom(client, states: [joinRule('knock')]);
      await tester.pumpWidget(host(KnockRequestBanner(room: member)));
      expect(find.byKey(KnockRequestBanner.bannerKey), findsNothing);

      final public = buildRoom(client,
          id: '!public:example.org',
          membership: matrix.Membership.leave,
          states: [joinRule('public')]);
      await tester.pumpWidget(host(KnockRequestBanner(room: public)));
      expect(find.byKey(KnockRequestBanner.bannerKey), findsNothing);
    });

    testWidgets('a request already sent shows as waiting', (tester) async {
      final client = LifecycleTestClient(FakeHomeserver());
      final room = buildRoom(client,
          membership: matrix.Membership.knock, states: [joinRule('knock')]);
      await tester.pumpWidget(host(KnockRequestBanner(room: room)));
      expect(find.text(KnockRequestBanner.messageKnockPending), findsOneWidget);
    });
  });

  group('answering knocks', () {
    test('the queue lists pending knocks with their notes', () {
      final room = buildRoom(LifecycleTestClient(FakeHomeserver()), states: [
        powerLevels(),
        joinRule('knock'),
        knockFrom(knocker, reason: 'Hi!', displayName: 'Knocker'),
        state(matrix.EventTypes.RoomMember, {'membership': 'join'},
            stateKey: '@member:example.org', sender: '@member:example.org'),
      ]);
      final requests = MatrixKnockingComponent(room).pendingKnocks;
      expect(requests.map((r) => r.userId), [knocker]);
      expect(requests.single.reason, 'Hi!');
      expect(requests.single.displayName, 'Knocker');
    });

    test('a moderator approves with invite and declines with kick', () async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server),
          states: [powerLevels(), joinRule('knock'), knockFrom(knocker)]);
      final knocking = MatrixKnockingComponent(room);

      expect(knocking.canModerate, isTrue);
      await knocking.approve(knocker);
      await knocking.deny(knocker, reason: 'Not now');

      expect(
          server.where('POST', '/rooms/!room:example.org/invite').single.body,
          {'user_id': knocker});
      expect(server.where('POST', '/rooms/!room:example.org/kick').single.body,
          {'user_id': knocker, 'reason': 'Not now'});
    });

    test('without the power, approving and declining are refused', () async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server), states: [
        powerLevels(ownLevel: 0),
        joinRule('knock'),
        knockFrom(knocker)
      ]);
      final knocking = MatrixKnockingComponent(room);

      expect(knocking.canModerate, isFalse);
      await expectLater(knocking.approve(knocker), throwsStateError);
      await expectLater(knocking.deny(knocker), throwsStateError);
      expect(server.seen, isEmpty);
    });

    testWidgets('a moderator lets someone in from the queue', (tester) async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server), states: [
        powerLevels(),
        joinRule('knock'),
        knockFrom(knocker, reason: 'Friend of Ana'),
      ]);

      await tester.pumpWidget(host(MatrixRoomKnockRequests(room)));
      expect(find.byKey(MatrixRoomKnockRequests.panelKey), findsOneWidget);
      expect(
          find.text(MatrixRoomKnockRequests.labelKnockReason('Friend of Ana')),
          findsOneWidget);

      await tester.tap(find.byKey(MatrixRoomKnockRequests.approveKey(knocker)));
      await settle(tester);

      expect(server.where('POST', '/invite').single.body, {'user_id': knocker});
      expect(server.where('POST', '/kick'), isEmpty);
    });

    testWidgets('a moderator declines with a reason', (tester) async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server),
          states: [powerLevels(), joinRule('knock'), knockFrom(knocker)]);

      await tester.pumpWidget(host(MatrixRoomKnockRequests(room)));
      await tester.tap(find.byKey(MatrixRoomKnockRequests.declineKey(knocker)));
      await settle(tester);
      await answerPrompt(tester, 'Members only',
          submit: MatrixRoomKnockRequests.promptDeclineKnock);

      expect(server.where('POST', '/kick').single.body,
          {'user_id': knocker, 'reason': 'Members only'});
      expect(server.where('POST', '/invite'), isEmpty);
    });

    testWidgets('someone without the power sees no moderation actions',
        (tester) async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server), states: [
        powerLevels(ownLevel: 0),
        joinRule('knock'),
        knockFrom(knocker),
      ]);

      await tester.pumpWidget(host(MatrixRoomKnockRequests(room)));

      expect(find.byKey(MatrixRoomKnockRequests.panelKey), findsNothing);
      expect(find.byKey(MatrixRoomKnockRequests.approveKey(knocker)),
          findsNothing);
      expect(find.byKey(MatrixRoomKnockRequests.declineKey(knocker)),
          findsNothing);
    });

    testWidgets('a room that takes no knocks and has none shows no queue',
        (tester) async {
      final room = buildRoom(LifecycleTestClient(FakeHomeserver()),
          states: [powerLevels(), joinRule('invite')]);
      await tester.pumpWidget(host(MatrixRoomKnockRequests(room)));
      expect(find.byKey(MatrixRoomKnockRequests.panelKey), findsNothing);
    });
  });
}
