// Criterion 2: what an ignored user sends is hidden from the timeline and
// their invites from the invite list, and both come back when they are
// unignored, without reopening the room or restarting.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart' as chunk;
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/invitation/invitation_component.dart';
import 'package:rooster/client/matrix/components/reporting/matrix_ignored_users.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';

import '../speed_log/fake_account.dart';
import 'fakes.dart';

const bob = '@bob:example.org';
const carol = '@carol:example.org';

matrix.Event message(matrix.Room room, String id, String sender) =>
    matrix.Event(
      type: matrix.EventTypes.Message,
      content: {'msgtype': 'm.text', 'body': 'hello from $sender'},
      eventId: id,
      senderId: sender,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      room: room,
    );

matrix.Event join(matrix.Room room, String id, String sender) => matrix.Event(
      type: matrix.EventTypes.RoomMember,
      stateKey: sender,
      content: {'membership': 'join'},
      eventId: id,
      senderId: sender,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(500),
      room: room,
    );

Future<(MatrixClient, MatrixTimeline)> roomTimeline() async {
  final client = await account(Script());
  final room = await plainRoom(client);
  final mx = room.matrixRoom;
  final timeline = MatrixTimeline(client, room, mx,
      initialTimeline: matrix.Timeline(
          room: mx,
          chunk: chunk.TimelineChunk(events: [
            message(mx, r'$bob2', bob),
            message(mx, r'$carol1', carol),
            message(mx, r'$own1', client.matrixClient.userID!),
            message(mx, r'$bob1', bob),
            join(mx, r'$bobjoin', bob),
          ])));
  return (client, timeline);
}

/// The ids of the events the timeline shows (hidden ones are drawn like
/// redacted ones: not at all).
List<String> shown(MatrixTimeline timeline) => [
      for (final e in timeline.events)
        if (!timeline.isEventRedacted(e)) e.eventId
    ];

Future<void> settleAsync() => Future<void>.delayed(Duration.zero);

void main() {
  setUpAll(prepareTests);

  group('timeline', () {
    test('hides an ignored user\'s messages, keeps their state events',
        () async {
      final (client, timeline) = await roomTimeline();
      expect(shown(timeline),
          [r'$bob2', r'$carol1', r'$own1', r'$bob1', r'$bobjoin']);

      await MatrixIgnoredUsers.of(client.matrixClient).ignore(bob);

      expect(shown(timeline), [r'$carol1', r'$own1', r'$bobjoin']);
      await timeline.close();
    });

    test('redraws their events when they are ignored and when unignored',
        () async {
      final (client, timeline) = await roomTimeline();
      final redrawn = <int>[];
      timeline.onChange.stream.listen(redrawn.add);
      final ignored = MatrixIgnoredUsers.of(client.matrixClient);

      await ignored.ignore(bob);
      await settleAsync();
      // Their two messages and their join, so the neighbours regroup.
      expect(redrawn, [0, 3, 4]);

      redrawn.clear();
      await ignored.unignore(bob);
      await settleAsync();
      expect(redrawn, [0, 3, 4]);
      expect(shown(timeline),
          [r'$bob2', r'$carol1', r'$own1', r'$bob1', r'$bobjoin']);
      await timeline.close();
    });

    test('follows a list that another session changed', () async {
      final (client, timeline) = await roomTimeline();

      await syncIgnoreList(client.matrixClient, [carol]);
      expect(shown(timeline), isNot(contains(r'$carol1')));

      await syncIgnoreList(client.matrixClient, []);
      expect(shown(timeline), contains(r'$carol1'));
      await timeline.close();
    });

    test('never hides our own messages', () async {
      final (client, timeline) = await roomTimeline();
      final mx = client.matrixClient;
      // Our ID on the list, written by some other client.
      await syncIgnoreList(mx, [mx.userID!]);
      expect(shown(timeline), contains(r'$own1'));
      await timeline.close();
    });
  });

  group('invites', () {
    Future<void> invitedBy(matrix.Client mx, String roomId, String sender) =>
        sync(
            mx,
            matrix.SyncUpdate(
                nextBatch: 'invite_$roomId',
                rooms: matrix.RoomsUpdate(invite: {
                  roomId: matrix.InvitedRoomUpdate(inviteState: [
                    matrix.StrippedStateEvent(
                      type: matrix.EventTypes.RoomMember,
                      stateKey: mx.userID,
                      senderId: sender,
                      content: {'membership': 'invite'},
                    ),
                  ]),
                })));

    Future<(MatrixClient, InvitationComponent)> invites() async {
      final client = await account(Script());
      final component = client.getComponent<InvitationComponent>()!;
      (component as NeedsPostLoginInit).postLoginInit();
      await invitedBy(client.matrixClient, '!frombob:example.org', bob);
      await invitedBy(client.matrixClient, '!fromcarol:example.org', carol);
      await settleAsync();
      return (client, component);
    }

    List<String> rooms(InvitationComponent c) =>
        [for (final i in c.invitations) i.roomId]..sort();

    test('an ignored user\'s invite leaves the list and comes back', () async {
      final (client, invitations) = await invites();
      expect(rooms(invitations),
          containsAll(['!frombob:example.org', '!fromcarol:example.org']));

      final ignored = MatrixIgnoredUsers.of(client.matrixClient);
      await ignored.ignore(bob);
      await settleAsync();
      expect(rooms(invitations), isNot(contains('!frombob:example.org')));
      expect(rooms(invitations), contains('!fromcarol:example.org'));
      // The invite is hidden, not declined.
      expect(
          client.matrixClient.getRoomById('!frombob:example.org')?.membership,
          matrix.Membership.invite);

      await ignored.unignore(bob);
      await settleAsync();
      expect(rooms(invitations), contains('!frombob:example.org'));
    });

    test('an invite from someone already ignored never shows', () async {
      final client = await account(Script());
      final mx = client.matrixClient;
      await syncIgnoreList(mx, [bob]);
      final component = client.getComponent<InvitationComponent>()!;
      (component as NeedsPostLoginInit).postLoginInit();

      await invitedBy(mx, '!late:example.org', bob);
      await settleAsync();

      expect(rooms(component), isNot(contains('!late:example.org')));
    });
  });
}
