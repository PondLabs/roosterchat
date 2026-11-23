// Criterion 2: the room settings switch lists the room in the public room
// directory or takes it out with `PUT /v3/directory/list/room/{roomId}`,
// and goes back when the homeserver answers M_FORBIDDEN.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/matrix/components/room_directory/matrix_room_directory_visibility.dart';
import 'package:rooster/ui/pages/settings/categories/room/general/matrix_room_directory_visibility_settings.dart';

import 'fakes.dart';

const roomId = '!room:example.org';
const directoryPath = '/_matrix/client/v3/directory/list/room/$roomId';

/// A directory that holds [published] and lets the change through unless
/// [refuse] says otherwise.
class DirectoryEntry {
  DirectoryEntry({this.published = false});
  bool published;
  http.Response Function()? refuse;

  http.Response? route(Seen request) {
    if (request.path != directoryPath) return null;
    if (request.method == 'GET') {
      return json({'visibility': published ? 'public' : 'private'});
    }
    final refused = refuse?.call();
    if (refused != null) return refused;
    published = (request.body as Map)['visibility'] == 'public';
    return json(<String, Object?>{});
  }
}

void main() {
  setUpAll(prepareTests);

  test('reads and sets the entry with GET and PUT', () async {
    final entry = DirectoryEntry();
    final script = Script()..routes.add(entry.route);
    final visibility =
        RoomDirectoryVisibility(joinedRoom(DirectoryTestClient(script)));

    expect(await visibility.load(), isFalse);
    await visibility.setPublished(true);
    await visibility.setPublished(false);

    final puts = script.where('PUT', directoryPath).toList();
    expect(puts.map((p) => p.body), [
      {'visibility': 'public'},
      {'visibility': 'private'},
    ]);
    expect(script.where('GET', directoryPath), hasLength(1));
  });

  test('only someone who could change the room address may change it', () {
    final script = Script();
    final client = DirectoryTestClient(script);
    expect(RoomDirectoryVisibility(joinedRoom(client)).canChange, isTrue);
    expect(
        RoomDirectoryVisibility(
                joinedRoom(client, id: '!other:example.org', ownLevel: 0))
            .canChange,
        isFalse);
  });

  Future<Script> pumpSettings(WidgetTester tester, DirectoryEntry entry) async {
    final script = Script()..routes.add(entry.route);
    final room = joinedRoom(DirectoryTestClient(script));
    await tester.pumpWidget(host(MatrixRoomDirectoryVisibilitySettings(room)));
    await settle(tester);
    return script;
  }

  bool switchValue(WidgetTester tester) => tester
      .widget<Switch>(
          find.byKey(MatrixRoomDirectoryVisibilitySettings.switchKey))
      .value;

  testWidgets('the switch publishes and unpublishes the room', (tester) async {
    final entry = DirectoryEntry();
    final script = await pumpSettings(tester, entry);
    expect(switchValue(tester), isFalse);

    await tester
        .tap(find.byKey(MatrixRoomDirectoryVisibilitySettings.switchKey));
    await settle(tester);
    expect(switchValue(tester), isTrue);
    expect(entry.published, isTrue);

    await tester
        .tap(find.byKey(MatrixRoomDirectoryVisibilitySettings.switchKey));
    await settle(tester);
    expect(switchValue(tester), isFalse);
    expect(script.where('PUT', directoryPath).map((p) => p.body), [
      {'visibility': 'public'},
      {'visibility': 'private'},
    ]);
  });

  for (final startPublished in [false, true]) {
    testWidgets(
        'M_FORBIDDEN puts the switch back (from published: $startPublished)',
        (tester) async {
      final entry = DirectoryEntry(published: startPublished)
        ..refuse = () => matrixError('M_FORBIDDEN');
      final script = await pumpSettings(tester, entry);
      expect(switchValue(tester), startPublished);

      await tester
          .tap(find.byKey(MatrixRoomDirectoryVisibilitySettings.switchKey));
      await settle(tester);

      expect(script.where('PUT', directoryPath).single.body,
          {'visibility': startPublished ? 'private' : 'public'});
      expect(switchValue(tester), startPublished);
      expect(
          find.text(MatrixRoomDirectoryVisibilitySettings
              .messageRoomDirectoryForbidden),
          findsOneWidget);
    });
  }

  testWidgets('another failure puts the switch back with a general message',
      (tester) async {
    final entry = DirectoryEntry()
      ..refuse = () => http.Response('Bad gateway', 502);
    await pumpSettings(tester, entry);

    await tester
        .tap(find.byKey(MatrixRoomDirectoryVisibilitySettings.switchKey));
    await settle(tester);

    expect(switchValue(tester), isFalse);
    expect(
        find.text(
            MatrixRoomDirectoryVisibilitySettings.messageRoomDirectoryFailed),
        findsOneWidget);
  });

  testWidgets('without the power the switch cannot be used', (tester) async {
    final script = Script()..routes.add(DirectoryEntry().route);
    final room = joinedRoom(DirectoryTestClient(script), ownLevel: 0);
    await tester.pumpWidget(host(MatrixRoomDirectoryVisibilitySettings(room)));
    await settle(tester);

    expect(
        tester
            .widget<Switch>(
                find.byKey(MatrixRoomDirectoryVisibilitySettings.switchKey))
            .onChanged,
        isNull);
    expect(script.where('PUT', directoryPath), isEmpty);
  });
}
