import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/ui/pages/matrix/room_address_settings/matrix_room_address_settings.dart';
import 'package:rooster/ui/pages/matrix/room_address_settings/matrix_room_address_settings_view.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'test_helpers.dart';

void main() {
  const roomId = '!addr/room:example.test';

  matrix.Room buildRoom(
    http.Client httpClient, {
    String? canonicalAlias,
    List<String>? altAliases,
  }) {
    final mx = TestMatrixClient(
      'addr_test',
      httpClient: httpClient,
      accessToken: 'test-token',
      userId: '@alice:example.test',
    );
    final room = matrix.Room(id: roomId, client: mx);
    if (canonicalAlias != null || altAliases != null) {
      room.setState(
        matrix.Event(
          type: matrix.EventTypes.RoomCanonicalAlias,
          stateKey: '',
          eventId: r'$alias_state',
          senderId: '@alice:example.test',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          content: {
            if (canonicalAlias != null) 'alias': canonicalAlias,
            if (altAliases != null) 'alt_aliases': altAliases,
          },
          room: room,
        ),
      );
    }
    return room;
  }

  group('MatrixRoomAddressSettings', () {
    testWidgets('fetches local aliases via stable v3 getLocalAliases endpoint',
        (tester) async {
      final seen = <Uri>[];
      final room = buildRoom(
        MockClient((request) async {
          seen.add(request.url);
          return http.Response(
            jsonEncode({
              'aliases': ['#local:example.test', '#main:example.test'],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        canonicalAlias: '#main:example.test',
        altAliases: ['#alt:other.test'],
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeDark.theme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: MatrixRoomAddressSettings(room),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(seen, hasLength(1));
      expect(seen.single.path, isNot(contains('org.matrix.msc2432')));
      expect(
        seen.single.path,
        '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/aliases',
      );
      final view = tester.widget<MatrixRoomAddressSettingsView>(
        find.byType(MatrixRoomAddressSettingsView),
      );
      expect(
        view.knownAliases,
        containsAll([
          '#local:example.test',
          '#main:example.test',
          '#alt:other.test',
        ]),
      );
      expect(
        view.publishedAliases,
        containsAll(['#main:example.test', '#alt:other.test']),
      );
      expect(view.publishedAliases, isNot(contains('#local:example.test')));
      expect(view.mainAlias, '#main:example.test');
    });

    testWidgets('degrades gracefully when getLocalAliases fails',
        (tester) async {
      final room = buildRoom(
        MockClient((request) async {
          return http.Response(
            jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'Denied'}),
            403,
            headers: {'content-type': 'application/json'},
          );
        }),
        canonicalAlias: '#main:example.test',
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeDark.theme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: MatrixRoomAddressSettings(room),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      final view = tester.widget<MatrixRoomAddressSettingsView>(
        find.byType(MatrixRoomAddressSettingsView),
      );
      expect(view.knownAliases, ['#main:example.test']);
    });
  });
}
