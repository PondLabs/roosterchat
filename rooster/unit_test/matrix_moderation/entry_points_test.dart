// Criterion 2 where people reach it: kicking and banning from a member's
// menu, deleting someone else's message from its menu, and inviting from
// the invite dialog all ask for an optional reason and send it.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart' as chunk;
import 'package:rooster/client/components/invitation/invitation_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/ui/molecules/profile/mini_profile_view.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:rooster/ui/molecules/user_list.dart';
import 'package:rooster/ui/organisms/invitation_view/send_invitation.dart';
import 'package:rooster/ui/organisms/moderation/moderation_reason_dialog.dart';
import 'package:rooster/utils/common_strings.dart';

import '../matrix_reporting_ignore/fakes.dart' show account;
import '../speed_log/fake_account.dart';
import 'fakes.dart';

const bob = '@bob:example.org';

/// Kick, ban, invite and redactions are taken; the user directory finds no
/// one, so the invite dialog offers the ID that was typed.
http.Response? moderationServer(Seen r) {
  if (r.method == 'POST' &&
      (r.path.endsWith('/kick') ||
          r.path.endsWith('/ban') ||
          r.path.endsWith('/invite'))) {
    return json(<String, Object?>{});
  }
  if (r.method == 'PUT' &&
      (r.path.contains('/redact/') ||
          r.path.contains('/send/m.room.redaction/'))) {
    return json({'event_id': r'$redaction'});
  }
  if (r.path.endsWith('/user_directory/search')) {
    return json({'results': <Object>[], 'limited': false});
  }
  if (r.path.endsWith('/profile/$bob')) {
    return json({'displayname': 'Bob'});
  }
  return null;
}

Future<(Script, MatrixClient, MatrixRoom, BuildContext)> setUp(
    WidgetTester tester) async {
  final script = Script()..routes.add(moderationServer);
  final (client, room) = (await tester.runAsync(() async {
    final client = await account(script);
    return (client, await plainRoom(client));
  }))!;
  putState(room.matrixRoom, matrix.EventTypes.RoomPowerLevels, {
    'users': {client.matrixClient.userID!: 100},
  });
  late BuildContext context;
  await tester.pumpWidget(host(Builder(builder: (c) {
    context = c;
    return const SizedBox();
  }), scroll: false));
  return (script, client, room, context);
}

Future<void> confirmReason(WidgetTester tester, String reason) async {
  await tester.pumpAndSettle();
  await tester.enterText(
      find.byKey(ModerationReasonDialog.reasonFieldKey), reason);
  await tester.tap(find.byKey(ModerationReasonDialog.confirmKey));
  await settle(tester);
}

void main() {
  setUpAll(prepareTests);

  for (final (name, path) in [
    (RoomMemberList.promptProfileKick, '/kick'),
    (RoomMemberList.promptProfileBan, '/ban'),
  ]) {
    testWidgets('"$name" in a member\'s menu sends the reason typed',
        (tester) async {
      final (script, _, room, context) = await setUp(tester);
      var done = false;

      RoomMemberList.userContextMenuItems(context,
              userId: bob,
              userDisplayName: 'Bob',
              room: room,
              isSelf: false,
              onUserKicked: () => done = true,
              onUserBanned: () => done = true)
          .singleWhere((i) => i.text == name)
          .onPressed!();
      await confirmReason(tester, ' too loud ');

      expect(
          script.where('POST', '/rooms/${room.matrixRoom.id}$path').single.body,
          {'user_id': bob, 'reason': 'too loud'});
      expect(done, isTrue);
    });
  }

  testWidgets('a refused ban is said in words, not as an exception',
      (tester) async {
    final (script, _, room, context) = await setUp(tester);
    script.routes.insert(
        0, (r) => r.path.endsWith('/ban') ? matrixError('M_FORBIDDEN') : null);
    var banned = false;

    RoomMemberList.userContextMenuItems(context,
            userId: bob,
            userDisplayName: 'Bob',
            room: room,
            isSelf: false,
            onUserBanned: () => banned = true)
        .singleWhere((i) => i.text == RoomMemberList.promptProfileBan)
        .onPressed!();
    await confirmReason(tester, '');

    expect(script.where('POST', '/ban').single.body, {'user_id': bob});
    expect(
        find.text(ModerationStrings.errorModerationForbidden), findsOneWidget);
    expect(banned, isFalse);
  });

  testWidgets('deleting someone else\'s message asks for a reason',
      (tester) async {
    final (script, client, room, context) = await setUp(tester);
    final mx = room.matrixRoom;
    final timeline = MatrixTimeline(client, room, mx,
        initialTimeline: matrix.Timeline(
            room: mx,
            chunk: chunk.TimelineChunk(events: [
              matrix.Event(
                type: matrix.EventTypes.Message,
                content: {'msgtype': 'm.text', 'body': 'spam'},
                eventId: r'$theirs',
                senderId: bob,
                originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
                room: mx,
              ),
            ])));

    final menu = TimelineEventMenu(
        timeline: timeline, event: timeline.events.single, context: context);
    menu.primaryActions
        .singleWhere((e) => e.name == CommonStrings.promptDelete)
        .action!(context);
    await confirmReason(tester, 'spam link');

    final sent = script.seen
        .where((s) =>
            s.path.contains('/redact/\$theirs/') ||
            s.path.contains('/send/m.room.redaction/'))
        .single;
    expect((sent.body as Map)['reason'], 'spam link');
    await tester.runAsync(timeline.close);
  });

  testWidgets('the invite dialog sends the reason typed', (tester) async {
    final (script, client, room, _) = await setUp(tester);
    await tester.pumpWidget(host(
        SendInvitationWidget(
            client, client.getComponent<InvitationComponent>()!,
            roomId: room.matrixRoom.id, displayName: 'Room'),
        scroll: false));

    // The suggested people load their profiles before the search hides them.
    await settle(tester);
    await tester.enterText(find.byType(TextField), bob);
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    // The directory found no one; the typed ID is offered.
    await tester.tap(find.byType(MiniProfileView));
    await confirmReason(tester, 'join us');

    expect(
        script.where('POST', '/rooms/${room.matrixRoom.id}/invite').single.body,
        {'user_id': bob, 'reason': 'join us'});
  });
}
