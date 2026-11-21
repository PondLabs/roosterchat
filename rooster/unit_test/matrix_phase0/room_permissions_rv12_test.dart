import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/settings/categories/room/permissions/matrix/matrix_room_permissions_page.dart';
import 'package:rooster/ui/pages/settings/categories/room/permissions/matrix/matrix_room_permissions_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'test_helpers.dart';

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  matrix.Room buildRoom({
    required String roomVersion,
    required String creatorId,
    List<String> additionalCreators = const [],
    required Map<String, Object?> powerLevelsContent,
    String selfId = '@creator:example.test',
    List<Map<String, dynamic>>? capturedPowerLevelWrites,
  }) {
    final mx = TestMatrixClient(
      'perms_test_$roomVersion',
      httpClient: MockClient((request) async {
        if (request.method == 'PUT' &&
            request.url.path.contains('/state/m.room.power_levels')) {
          capturedPowerLevelWrites?.add(
            jsonDecode(request.body) as Map<String, dynamic>,
          );
          return http.Response(
            jsonEncode({'event_id': r'$pl_written'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
      }),
      accessToken: 'test-token',
      userId: selfId,
    );

    final room = matrix.Room(
      id: '!room_$roomVersion:example.test',
      client: mx,
      membership: matrix.Membership.join,
    );
    room.setState(
      matrix.Event(
        type: matrix.EventTypes.RoomCreate,
        stateKey: '',
        eventId: r'$create',
        senderId: creatorId,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(100),
        content: {
          'room_version': roomVersion,
          if (additionalCreators.isNotEmpty)
            'additional_creators': additionalCreators,
        },
        room: room,
      ),
    );
    room.setState(
      matrix.Event(
        type: matrix.EventTypes.RoomPowerLevels,
        stateKey: '',
        eventId: r'$pl',
        senderId: creatorId,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(200),
        content: powerLevelsContent,
        room: room,
      ),
    );
    return room;
  }

  group('MatrixRoomPermissionsPage RV12 vs RV11', () {
    testWidgets(
      'RV12 displays immutable creators section, omits synthetic PL 150 role, '
      'and never writes creators or PL 150 in m.room.power_levels.users',
      (tester) async {
        final writes = <Map<String, dynamic>>[];
        final room = buildRoom(
          roomVersion: '12',
          creatorId: '@creator:example.test',
          additionalCreators: const ['@cocreator:example.test'],
          powerLevelsContent: {
            'state_default': 50,
            'events_default': 0,
            'events': {'m.room.name': 50},
            'users': {
              '@creator:example.test': 150,
              '@cocreator:example.test': 100,
              '@admin:example.test': 100,
            },
          },
          capturedPowerLevelWrites: writes,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeDark.theme,
            home: Scaffold(body: MatrixRoomPermissionsPage(room)),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(MatrixRoomPermissionsPage.immutableCreatorsKey),
          findsOneWidget,
        );
        expect(find.textContaining('@creator:example.test'), findsOneWidget);
        expect(find.textContaining('@cocreator:example.test'), findsOneWidget);
        // Synthetic power level 150 must not appear in the role list.
        expect(find.text('150'), findsNothing);

        final view = tester.widget<MatrixRoomPermissionsView>(
          find.byType(MatrixRoomPermissionsView),
        );
        expect(view.powerLevels.any((r) => r.powerlevel == 150), isFalse);

        final namePerm = view.permissions.firstWhere(
          (p) => p.key == 'm.room.name',
        );
        namePerm.powerLevel = 100;
        await tester.runAsync(() => view.setPermissions!(view.permissions));

        expect(writes, hasLength(1));
        final written = writes.single;
        final users = written['users'] as Map<String, dynamic>;
        expect(users.containsKey('@creator:example.test'), isFalse);
        expect(users.containsKey('@cocreator:example.test'), isFalse);
        expect(users.values.contains(150), isFalse);
        expect(users['@admin:example.test'], 100);
        expect((written['events'] as Map)['m.room.name'], 100);
      },
    );

    testWidgets(
      'RV11 does not show RV12 immutable creators section and preserves '
      'creator power level in m.room.power_levels.users',
      (tester) async {
        final writes = <Map<String, dynamic>>[];
        final room = buildRoom(
          roomVersion: '11',
          creatorId: '@creator:example.test',
          powerLevelsContent: {
            'events_default': 0,
            'events': {'m.room.topic': 50},
            'users': {
              '@creator:example.test': 100,
              '@mod:example.test': 50,
            },
          },
          capturedPowerLevelWrites: writes,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeDark.theme,
            home: Scaffold(body: MatrixRoomPermissionsPage(room)),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(MatrixRoomPermissionsPage.immutableCreatorsKey),
          findsNothing,
        );
        expect(find.text('150'), findsNothing);

        final view = tester.widget<MatrixRoomPermissionsView>(
          find.byType(MatrixRoomPermissionsView),
        );
        final topicPerm = view.permissions.firstWhere(
          (p) => p.key == 'm.room.topic',
        );
        topicPerm.powerLevel = 100;
        await tester.runAsync(() => view.setPermissions!(view.permissions));

        expect(writes, hasLength(1));
        final written = writes.single;
        final users = written['users'] as Map<String, dynamic>;
        expect(users['@creator:example.test'], 100);
        expect(users['@mod:example.test'], 50);
        expect(users.values.contains(150), isFalse);
        expect((written['events'] as Map)['m.room.topic'], 100);
      },
    );
  });
}
