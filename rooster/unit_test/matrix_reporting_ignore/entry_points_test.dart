// Where reporting and ignoring are reached: a message's menu (someone
// else's message only), a room's menu in the sidebar, and the menu of
// someone's profile card (report, ignore after asking, stop ignoring).
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart' as chunk;
import 'package:rooster/client/matrix/components/reporting/matrix_ignored_users.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/ui/atoms/room_panel_actions.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/moderation/ignore_user_actions.dart';
import 'package:rooster/ui/organisms/moderation/profile_moderation_actions.dart';
import 'package:rooster/ui/organisms/moderation/report_content_dialog.dart';
import 'package:rooster/utils/common_strings.dart';

import '../speed_log/fake_account.dart';
import 'fakes.dart';

const bob = '@bob:example.org';

http.Response? acceptReports(Seen r) =>
    r.method == 'POST' && r.path.contains('/report')
        ? json(<String, Object?>{})
        : null;

Future<(Script, MatrixClient, MatrixRoom, BuildContext)> setUp(
    WidgetTester tester) async {
  final script = Script()..routes.add(acceptReports);
  final (client, room) = (await tester.runAsync(() async {
    final client = await account(script);
    return (client, await plainRoom(client));
  }))!;
  late BuildContext context;
  await tester.pumpWidget(host(Builder(builder: (c) {
    context = c;
    return const SizedBox();
  }), scroll: false));
  return (script, client, room, context);
}

matrix.Event message(matrix.Room room, String id, String sender) =>
    matrix.Event(
      type: matrix.EventTypes.Message,
      content: {'msgtype': 'm.text', 'body': 'hi'},
      eventId: id,
      senderId: sender,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      room: room,
    );

void main() {
  setUpAll(prepareTests);

  testWidgets('someone else\'s message is reported from its menu',
      (tester) async {
    final (script, client, room, context) = await setUp(tester);
    final mx = room.matrixRoom;
    final timeline = MatrixTimeline(client, room, mx,
        initialTimeline: matrix.Timeline(
            room: mx,
            chunk: chunk.TimelineChunk(events: [
              message(mx, r'$theirs', bob),
              message(mx, r'$ours', client.matrixClient.userID!),
            ])));
    Map<String, TimelineEventMenuEntry> entries(int i) {
      final menu = TimelineEventMenu(
          timeline: timeline, event: timeline.events[i], context: context);
      return {
        for (final e in [...menu.primaryActions, ...menu.secondaryActions])
          e.name: e
      };
    }

    expect(entries(1).keys,
        isNot(contains(ReportContentDialog.promptReportMessage)));
    final report = entries(0)[ReportContentDialog.promptReportMessage]!;

    report.action!(context);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ReportContentDialog.sendKey));
    await settle(tester);

    expect(
        script.where('POST', '/rooms/${mx.id}/report/\$theirs'), hasLength(1));
    expect(find.text(ReportContentDialog.messageReportSent), findsOneWidget);
    await tester.runAsync(timeline.close);
  });

  testWidgets('a room is reported from its menu in the sidebar',
      (tester) async {
    final (script, _, room, context) = await setUp(tester);

    final item = RoomPanelActions.menuItems(context, room)
        .singleWhere((i) => i.text == ReportContentDialog.promptReportRoom);
    item.onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ReportContentDialog.sendKey));
    await settle(tester);

    expect(script.where('POST', '/rooms/${room.matrixRoom.id}/report'),
        hasLength(1));
  });

  group('profile card', () {
    List<String> texts(List<ProfileMenuAction> actions) =>
        [for (final a in actions) a.text];

    testWidgets('reports the user', (tester) async {
      final (script, client, _, context) = await setUp(tester);

      ProfileModerationActions.of(context, client, bob)
          .singleWhere((a) => a.text == ReportContentDialog.promptReportUser)
          .onPressed();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ReportContentDialog.sendKey));
      await settle(tester);

      expect(script.where('POST', '/users/$bob/report'), hasLength(1));
    });

    testWidgets('ignores after asking, then offers to stop ignoring',
        (tester) async {
      final (script, client, _, context) = await setUp(tester);
      var changed = 0;
      final actions = ProfileModerationActions.of(context, client, bob,
          displayName: 'Bob', onChanged: () => changed++);
      expect(texts(actions), [
        ReportContentDialog.promptReportUser,
        IgnoreUserActions.promptIgnoreUser,
      ]);

      actions[1].onPressed();
      await tester.pumpAndSettle();
      expect(find.text(IgnoreUserActions.labelIgnoreUserConfirmation('Bob')),
          findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byType(ConfirmationDialogWidget),
          matching: find.text(IgnoreUserActions.promptIgnoreUser)));
      await settle(tester);

      expect(writtenUsers(ignoreListWrites(script).single), {bob: {}});
      expect(changed, 1);
      final after = ProfileModerationActions.of(context, client, bob);
      expect(texts(after), contains(IgnoreUserActions.promptUnignoreUser));

      after[1].onPressed();
      await settle(tester);
      expect(
          MatrixIgnoredUsers.of(client.matrixClient).isIgnored(bob), isFalse);
    });

    testWidgets('a declined confirmation ignores nobody', (tester) async {
      final (script, client, _, context) = await setUp(tester);

      ProfileModerationActions.of(context, client, bob)[1].onPressed();
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(ConfirmationDialogWidget),
          matching: find.text(CommonStrings.promptNo)));
      await settle(tester);

      expect(ignoreListWrites(script), isEmpty);
    });

    testWidgets(
        'our own card has neither entry, and ignoring ourselves is '
        'refused with a sentence', (tester) async {
      final (script, client, _, context) = await setUp(tester);
      final self = client.matrixClient.userID!;

      expect(ProfileModerationActions.of(context, client, self), isEmpty);

      IgnoreUserActions.confirmAndIgnore(context, client.matrixClient, self);
      await tester.pumpAndSettle();
      expect(find.text(IgnoreUserActions.errorIgnoreSelf), findsOneWidget);
      expect(ignoreListWrites(script), isEmpty);
    });
  });
}
