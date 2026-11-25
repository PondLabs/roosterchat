// Criterion 4: `m.marked_unread` (v1.12, MSC2867) is read from the stable
// type and from the legacy `com.famedly.marked_unread`, always written to
// `m.marked_unread`, lights the room's dot in the sidebar with
// `notification_count == 0`, and is cleared when the room is read.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/sidebar_entries/matrix_room_marked_unread.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/ui/atoms/dot_indicator.dart';
import 'package:rooster/ui/atoms/room_panel.dart';
import 'package:rooster/ui/atoms/room_panel_actions.dart';
import 'package:rooster/ui/atoms/room_panel_view.dart';

import '../speed_log/fake_account.dart';
import 'fakes.dart';

/// Room account data PUTs are answered here; the rest by the SDK's fake.
http.Response? http200(Seen r) =>
    r.method == 'PUT' && r.path.contains('/account_data/')
        ? json(<String, Object?>{})
        : null;

Future<(Script, MatrixRoom)> account(String name) async {
  final script = Script()..routes.add(http200);
  final client = await fakeAccount(name, ScriptedAccountTransport(script));
  final room = await plainRoom(client);
  script.seen.clear();
  return (script, room);
}

/// Room account data arrives in a sync.
Future<void> syncAccountData(
    MatrixRoom room, Map<String, Map<String, Object?>> data) async {
  final mx = room.matrixRoom.client;
  await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
        nextBatch: 'data_${data.hashCode}',
        rooms: matrix.RoomsUpdate(join: {
          room.matrixRoom.id: matrix.JoinedRoomUpdate(accountData: [
            for (final entry in data.entries)
              matrix.BasicEvent(type: entry.key, content: entry.value),
          ]),
        }),
      )));
  await Future<void>.delayed(Duration.zero);
}

Iterable<Seen> markWrites(Script script) => script.seen
    .where((s) => s.method == 'PUT' && s.path.contains('marked_unread'));

void main() {
  setUpAll(prepareTests);

  var n = 0;
  String name() =>
      'marked_unread_${n++}_${DateTime.now().microsecondsSinceEpoch}';

  test('reads the legacy type', () async {
    final (_, room) = await account(name());
    expect(MatrixMarkedUnread.isMarked(room.matrixRoom), isFalse);

    await syncAccountData(room, {
      MatrixMarkedUnread.legacyType: {'unread': true}
    });

    expect(MatrixMarkedUnread.isMarked(room.matrixRoom), isTrue);
    expect(room.notificationCount, 0);
    expect(RoomPanelActions.showsUnreadDot(room), isTrue);
  });

  test('reads the stable type, which wins over the legacy one', () async {
    final (_, room) = await account(name());

    await syncAccountData(room, {
      MatrixMarkedUnread.stableType: {'unread': true}
    });
    expect(MatrixMarkedUnread.isMarked(room.matrixRoom), isTrue);

    await syncAccountData(room, {
      MatrixMarkedUnread.stableType: {'unread': false},
      MatrixMarkedUnread.legacyType: {'unread': true},
    });
    expect(MatrixMarkedUnread.isMarked(room.matrixRoom), isFalse);
    expect(RoomPanelActions.showsUnreadDot(room), isFalse);
  });

  test('marking writes m.marked_unread, never the legacy type', () async {
    final (script, room) = await account(name());

    await MatrixMarkedUnread.setMarked(room.matrixRoom, true);

    final write = markWrites(script).single;
    expect(write.path, endsWith('/account_data/m.marked_unread'));
    expect(write.path, contains('/rooms/${room.matrixRoom.id}/'));
    expect(write.body, {'unread': true});
    expect(MatrixMarkedUnread.isMarked(room.matrixRoom), isTrue,
        reason: 'the local copy changes before the server answers');

    // Already marked: nothing to send.
    await MatrixMarkedUnread.setMarked(room.matrixRoom, true);
    expect(markWrites(script), hasLength(1));
  });

  test('a legacy mark is cleared through m.marked_unread', () async {
    final (script, room) = await account(name());
    await syncAccountData(room, {
      MatrixMarkedUnread.legacyType: {'unread': true}
    });

    await MatrixMarkedUnread.setMarked(room.matrixRoom, false);

    final write = markWrites(script).single;
    expect(write.path, endsWith('/account_data/m.marked_unread'));
    expect(write.body, {'unread': false});
    expect(script.seen.where((s) => s.path.contains('com.famedly')), isEmpty);
    expect(MatrixMarkedUnread.isMarked(room.matrixRoom), isFalse);
  });

  test('reading the room clears the mark', () async {
    final (script, room) = await account(name());
    await syncAccountData(room, {
      MatrixMarkedUnread.legacyType: {'unread': true}
    });

    // Both the read marker of the timeline and "Mark as Read" end here.
    room.clearUnreadCountsLocally();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(markWrites(script).single.body, {'unread': false});
    expect(RoomPanelActions.showsUnreadDot(room), isFalse);

    // Read again with no mark: nothing sent.
    room.clearUnreadCountsLocally();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(markWrites(script), hasLength(1));
  });

  testWidgets('the room panel shows the dot with no notification',
      (tester) async {
    final (_, room) = (await tester.runAsync(() => account(name())))!;
    await tester.pumpWidget(host(RoomPanel(room)));
    await tester.pump();
    expect(room.notificationCount, 0);
    expect(find.byType(DotIndicator), findsNothing);

    await tester.runAsync(() => syncAccountData(room, {
          MatrixMarkedUnread.legacyType: {'unread': true}
        }));
    await tester.pump();
    expect(
        tester.widget<RoomPanelView>(find.byType(RoomPanelView)).markedUnread,
        isTrue);
    expect(find.byType(DotIndicator), findsOneWidget);

    room.clearUnreadCountsLocally();
    await settle(tester);
    expect(find.byType(DotIndicator), findsNothing);
  });

  testWidgets('"Mark as Unread" is in the room menu until it is marked',
      (tester) async {
    final (script, room) = (await tester.runAsync(() => account(name())))!;
    late BuildContext context;
    await tester.pumpWidget(host(Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));

    final item = RoomPanelActions.menuItems(context, room)
        .singleWhere((i) => i.text == RoomPanelActions.promptRoomMarkAsUnread);
    await tester.runAsync(() async {
      await (item.onPressed!() as Future<void>);
    });

    expect(markWrites(script).single.body, {'unread': true});
    expect(
        RoomPanelActions.menuItems(context, room)
            .where((i) => i.text == RoomPanelActions.promptRoomMarkAsUnread),
        isEmpty);
  });
}
