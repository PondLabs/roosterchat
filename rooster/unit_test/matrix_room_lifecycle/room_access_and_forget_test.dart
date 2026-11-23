// Criterion 4: history visibility and guest access change only with the
// power to, and forgetting a left room sends no redundant /forget when the
// homeserver forgets on leave by itself (m.forget_forced_upon_leave,
// Matrix v1.18, MSC4267), telling the person so instead.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/room_lifecycle/matrix_archived_rooms.dart';
import 'package:rooster/ui/pages/settings/categories/account/account_state/archived_rooms_view.dart';
import 'package:rooster/ui/pages/settings/categories/room/security/matrix_room_history_access_settings.dart';

import 'fakes.dart';

/// [MatrixArchivedRooms] with the archive given, not synced.
class FixedArchive extends MatrixArchivedRooms {
  FixedArchive(super.client, this.rooms);
  final List<matrix.Room> rooms;

  @override
  Future<List<matrix.Room>> load() async => rooms;
}

Map<String, Object?> forced(bool enabled) => {
      'm.forget_forced_upon_leave': {'enabled': enabled},
    };

void main() {
  setUpAll(preparePreferences);

  group('history visibility', () {
    testWidgets('with the power, picking an option sends the state event',
        (tester) async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server), states: [
        powerLevels(),
        state(matrix.EventTypes.HistoryVisibility,
            {'history_visibility': 'shared'}),
      ]);

      await tester.pumpWidget(host(MatrixRoomHistoryVisibilitySettings(room)));
      await tester.tap(
          find.text(MatrixRoomHistoryVisibilitySettings.labelHistoryJoined));
      await settle(tester);

      final put =
          server.where('PUT', '/state/m.room.history_visibility').single;
      expect(put.body, {'history_visibility': 'joined'});
      expect(
          find.text(MatrixRoomHistoryVisibilitySettings
              .messageRoomSettingNoPermission),
          findsNothing);
    });

    testWidgets('without the power, nothing is sent and it says why',
        (tester) async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server), states: [
        powerLevels(ownLevel: 0),
        state(matrix.EventTypes.HistoryVisibility,
            {'history_visibility': 'shared'}),
      ]);

      await tester.pumpWidget(host(MatrixRoomHistoryVisibilitySettings(room)));
      await tester.tap(find
          .text(MatrixRoomHistoryVisibilitySettings.labelHistoryWorldReadable));
      await settle(tester);

      expect(server.where('PUT', '/state/'), isEmpty);
      expect(
          find.text(MatrixRoomHistoryVisibilitySettings
              .messageRoomSettingNoPermission),
          findsOneWidget);
    });
  });

  group('guest access', () {
    testWidgets('with the power, guests can be let in', (tester) async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server), states: [
        powerLevels(),
      ]);

      await tester.pumpWidget(host(MatrixRoomGuestAccessSettings(room)));
      await tester
          .tap(find.text(MatrixRoomGuestAccessSettings.labelGuestsCanJoin));
      await settle(tester);

      expect(server.where('PUT', '/state/m.room.guest_access').single.body,
          {'guest_access': 'can_join'});
    });

    testWidgets('without the power, nothing is sent', (tester) async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server), states: [
        powerLevels(ownLevel: 0),
        state(matrix.EventTypes.GuestAccess, {'guest_access': 'can_join'}),
      ]);

      await tester.pumpWidget(host(MatrixRoomGuestAccessSettings(room)));
      await tester
          .tap(find.text(MatrixRoomGuestAccessSettings.labelGuestsForbidden));
      await settle(tester);

      expect(server.where('PUT', '/state/'), isEmpty);
    });

    testWidgets('a power level just for guest access is respected',
        (tester) async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server), states: [
        powerLevels(ownLevel: 60, extra: {
          'events': {matrix.EventTypes.GuestAccess: 75},
        }),
      ]);

      await tester.pumpWidget(host(MatrixRoomGuestAccessSettings(room)));
      await tester
          .tap(find.text(MatrixRoomGuestAccessSettings.labelGuestsCanJoin));
      await settle(tester);

      expect(server.where('PUT', '/state/'), isEmpty);
    });
  });

  group('forgetting rooms', () {
    matrix.Room leftRoom(matrix.Client client) => buildRoom(client,
            id: '!old:example.org',
            membership: matrix.Membership.leave,
            states: [
              state(matrix.EventTypes.RoomName, {'name': 'Old room'}),
            ]);

    test('forced upon leave: no /forget, and the outcome says so', () async {
      final server = FakeHomeserver(capabilities: forced(true));
      final client = LifecycleTestClient(server);
      final archive = MatrixArchivedRooms(client);

      final outcome = await archive.forget(leftRoom(client));

      expect(outcome, ForgetOutcome.forcedByServer);
      expect(server.where('POST', '/forget'), isEmpty);
      expect(client.forgetting.forgotten, isEmpty);
    });

    test('not forced: /forget is sent', () async {
      final server = FakeHomeserver(capabilities: forced(false));
      final client = LifecycleTestClient(server);

      final outcome =
          await MatrixArchivedRooms(client).forget(leftRoom(client));

      expect(outcome, ForgetOutcome.forgotten);
      expect(
          server.where('POST', '/rooms/!old:example.org/forget'), hasLength(1));
      expect(client.forgetting.forgotten, ['!old:example.org']);
    });

    test('a server that does not say is taken not to force it, asked once',
        () async {
      final server = FakeHomeserver();
      final client = LifecycleTestClient(server);
      final archive = MatrixArchivedRooms(client);

      expect(await archive.forgetForcedUponLeave(), isFalse);
      await archive.forget(leftRoom(client));

      expect(server.where('POST', '/forget'), hasLength(1));
      expect(server.where('GET', '/capabilities'), hasLength(1));
    });

    testWidgets('forced: the view tells the person and offers no Forget',
        (tester) async {
      final server = FakeHomeserver(capabilities: forced(true));
      final client = LifecycleTestClient(server);
      final room = leftRoom(client);

      await tester
          .pumpWidget(host(ArchivedRoomsView(FixedArchive(client, [room]))));
      await tester.tap(find.text(ArchivedRoomsView.promptLoadArchivedRooms));
      await settle(tester);

      expect(find.byKey(ArchivedRoomsView.forcedNoticeKey), findsOneWidget);
      expect(find.text('Old room'), findsOneWidget);
      expect(find.byKey(ArchivedRoomsView.forgetKey(room.id)), findsNothing);
      expect(server.where('POST', '/forget'), isEmpty);
    });

    testWidgets('not forced: Forget asks, then forgets the room',
        (tester) async {
      final server = FakeHomeserver(capabilities: forced(false));
      final client = LifecycleTestClient(server);
      final room = leftRoom(client);

      await tester
          .pumpWidget(host(ArchivedRoomsView(FixedArchive(client, [room]))));
      await tester.tap(find.text(ArchivedRoomsView.promptLoadArchivedRooms));
      await settle(tester);
      expect(find.byKey(ArchivedRoomsView.forcedNoticeKey), findsNothing);

      await tester.tap(find.byKey(ArchivedRoomsView.forgetKey(room.id)));
      await settle(tester);
      expect(find.text(ArchivedRoomsView.labelForgetRoomPrompt('Old room')),
          findsOneWidget);
      // The dialog's own Forget button, not the list's.
      await tester.tap(find.text(ArchivedRoomsView.promptForgetRoom).last);
      await settle(tester);

      expect(
          server.where('POST', '/rooms/!old:example.org/forget'), hasLength(1));
      expect(find.text('Old room'), findsNothing);
      expect(find.text(ArchivedRoomsView.messageRoomForgotten), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
