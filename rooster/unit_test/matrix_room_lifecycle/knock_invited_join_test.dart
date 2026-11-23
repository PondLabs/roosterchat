// Regression tests for c2-1 (Criterion 3): someone invited to a `knock`
// room keeps a working Join in JoinRoomView and SpaceSummary. An approved
// request to join is an invite, and the auth rules (room version 7 on) take
// a knock only when the current membership is not ban, invite or join, so
// "Request to join" there could only fail. A request sent from the space
// stops showing as waiting once the sync shows what became of it.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/organisms/chat/knock_request_banner.dart';
import 'package:rooster/ui/organisms/space_summary/space_summary.dart';
import 'package:rooster/ui/pages/get_or_create_room/join_room_view.dart';
import 'package:rooster/utils/common_strings.dart';

import '../speed_log/fake_account.dart';
import 'fakes.dart';
import 'knock_ui_fakes.dart';

const spaceId = '!space:example.org';
const clubId = '!space_knock:example.org';

Future<void> sync(
    matrix.Client mx, String batch, matrix.RoomsUpdate rooms) async {
  await mx.database.transaction(
      () => mx.handleSync(matrix.SyncUpdate(nextBatch: batch, rooms: rooms)));
  // The Rooster client follows the SDK's onSync event.
  await Future<void>.delayed(Duration.zero);
}

/// An invite to the `knock` room [roomId] arrives in the sync.
Future<void> inviteTo(matrix.Client mx, String roomId) => sync(
    mx,
    'invite_$roomId',
    matrix.RoomsUpdate(invite: {
      roomId: matrix.InvitedRoomUpdate(inviteState: [
        matrix.StrippedStateEvent(
          type: matrix.EventTypes.RoomJoinRules,
          stateKey: '',
          senderId: '@mod:example.org',
          content: {'join_rule': 'knock'},
        ),
        matrix.StrippedStateEvent(
          type: matrix.EventTypes.RoomMember,
          stateKey: mx.userID,
          senderId: '@mod:example.org',
          content: {'membership': 'invite'},
        ),
      ]),
    }));

/// We are in the space [spaceId], whose child [clubId] is a `knock` room
/// (the fake hierarchy adds a `knock_restricted` one this space lets in).
Future<void> joinSpace(matrix.Client mx) => sync(
    mx,
    'space_1',
    matrix.RoomsUpdate(join: {
      spaceId: matrix.JoinedRoomUpdate(state: [
        matrix.MatrixEvent(
          type: matrix.EventTypes.RoomCreate,
          stateKey: '',
          senderId: mx.userID!,
          eventId: r'$create_space',
          originServerTs: DateTime.now(),
          content: {'type': 'm.space'},
        ),
        matrix.MatrixEvent(
          type: matrix.EventTypes.RoomMember,
          stateKey: mx.userID,
          senderId: mx.userID!,
          eventId: r'$join_space',
          originServerTs: DateTime.now(),
          content: {'membership': 'join'},
        ),
        matrix.MatrixEvent(
          type: matrix.EventTypes.SpaceChild,
          stateKey: clubId,
          senderId: mx.userID!,
          eventId: r'$child_knock',
          originServerTs: DateTime.now(),
          content: {
            'via': ['club.example'],
          },
        ),
      ]),
    }));

void main() {
  setUpAll(prepareKnockUi);

  Future<MatrixClient> account(WidgetTester tester, String name) async {
    final account = (await tester
        .runAsync(() => fakeAccount(name, KnockPreviewTransport())))!;
    addTearDown(() async {
      await tester.runAsync(
          () => account.getMatrixClient().dispose(closeDatabase: true));
    });
    return account;
  }

  Finder pendingText() =>
      find.text(KnockRequestBanner.messageKnockPending, findRichText: true);

  testWidgets(
      'c2-1: JoinRoomView keeps Join for a knock room we are invited to '
      '(an approved knock is an invite)', (tester) async {
    final client = await account(tester, 'c2_1_join_view');
    final mx = client.getMatrixClient();
    await tester.runAsync(() => inviteTo(mx, '!knock:example.org'));
    expect(mx.getRoomById('!knock:example.org')?.membership,
        matrix.Membership.invite);

    await tester.pumpWidget(host(SizedBox(
      height: 500,
      child: JoinRoomView(
        client,
        asSpace: false,
        initialRoomAddress: '!knock:example.org',
      ),
    )));
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);

    expect(find.text('Knock Room'), findsOneWidget);
    expect(find.text('Join Room!'), findsOneWidget);
    expect(find.text(KnockRequestBanner.promptRequestToJoin), findsNothing);
    expect(pendingText(), findsNothing);
  });

  testWidgets(
      'c2-1: SpaceSummary keeps Join for a knock child room we are invited to',
      (tester) async {
    final client = await account(tester, 'c2_1_space_summary');
    final mx = client.getMatrixClient();
    await tester.runAsync(() async {
      await joinSpace(mx);
      await inviteTo(mx, clubId);
    });

    await tester
        .pumpWidget(host(SpaceSummary(space: client.getSpace(spaceId)!)));
    await settle(tester);

    expect(find.text('Private Club'), findsOneWidget);
    // The fake hierarchy also lists 'Space Members Or Knock' (knock_restricted,
    // allowed via this space): Join + Request to join. Private Club, which we
    // are invited to, must show Join too and no Request to join.
    expect(find.text(KnockRequestBanner.promptRequestToJoin), findsOneWidget);
    expect(find.text(CommonStrings.promptJoin), findsNWidgets(2));
  });

  testWidgets(
      'c2-1: a request sent from SpaceSummary gives way to Join once it is '
      'approved', (tester) async {
    final client = await account(tester, 'c2_1_space_approved');
    final mx = client.getMatrixClient();
    await tester.runAsync(() => joinSpace(mx));
    final space = client.getSpace(spaceId)!;

    await tester.pumpWidget(host(SpaceSummary(space: space)));
    await settle(tester);
    await tapVisible(
        tester, find.text(KnockRequestBanner.promptRequestToJoin).first);
    await settle(tester);
    await answerPrompt(tester, 'From team space',
        submit: KnockRequestBanner.promptSendKnock);
    expect(pendingText(), findsOneWidget);

    // A moderator lets us in: the approval arrives as an invite.
    await tester.runAsync(() => inviteTo(mx, clubId));
    await tester.pumpWidget(host(SpaceSummary(space: space)));
    await settle(tester);

    expect(pendingText(), findsNothing);
    expect(find.text(CommonStrings.promptJoin), findsNWidgets(2));
    expect(find.text(KnockRequestBanner.promptRequestToJoin), findsOneWidget);
  });

  testWidgets(
      'c2-1: a request sent from SpaceSummary that is declined can be '
      'sent again', (tester) async {
    final client = await account(tester, 'c2_1_space_declined');
    final mx = client.getMatrixClient();
    await tester.runAsync(() => joinSpace(mx));
    final space = client.getSpace(spaceId)!;

    await tester.pumpWidget(host(SpaceSummary(space: space)));
    await settle(tester);
    await tapVisible(
        tester, find.text(KnockRequestBanner.promptRequestToJoin).first);
    await settle(tester);
    await answerPrompt(tester, 'From team space',
        submit: KnockRequestBanner.promptSendKnock);

    // Our knock becomes known locally: still waiting. (The SDK's /sync does
    // not read `rooms.knock` yet, so the room is put there by hand.)
    final club = matrix.Room(
        id: clubId, client: mx, membership: matrix.Membership.knock);
    mx.rooms.add(club);
    await tester.pumpWidget(host(SpaceSummary(space: space)));
    await settle(tester);
    expect(pendingText(), findsOneWidget);

    // A moderator declines (a kick): we are out of the room again.
    club.membership = matrix.Membership.leave;
    await tester.pumpWidget(host(SpaceSummary(space: space)));
    await settle(tester);

    expect(pendingText(), findsNothing);
    expect(find.text(KnockRequestBanner.promptRequestToJoin), findsNWidgets(2));
    expect(find.text(CommonStrings.promptJoin), findsOneWidget);
  });
}
