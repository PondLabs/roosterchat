// Criterion 5: `m.lowpriority` is toggled and the user's own `u.*` tags are
// added and removed with `PUT`/`DELETE /tags/{tag}`; empty names and tags
// outside a valid namespace are refused before any request.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/sidebar_entries/matrix_room_tags.dart';
import 'package:rooster/ui/atoms/room_panel_actions.dart';

import 'fakes.dart';

const roomId = '!room:example.org';
const tagsPath = '/_matrix/client/v3/user/$self/rooms/$roomId/tags/';

http.Response? tagServer(Seen request) =>
    request.path.startsWith(tagsPath) ? json(<String, Object?>{}) : null;

/// The tags arrive in the room's account data, as after a sync.
void setTags(matrix.Room room, Map<String, Object?> tags) {
  room.roomAccountData['m.tag'] =
      matrix.BasicEvent(type: 'm.tag', content: {'tags': tags});
}

List<String> calls(Script script) => script.seen
    .where((s) => s.path.startsWith(tagsPath))
    .map((s) => '${s.method} ${s.path.substring(tagsPath.length)}')
    .toList();

void main() {
  late Script script;
  late matrix.Room room;
  late MatrixRoomTags tags;

  setUp(() {
    script = Script()..routes.add(tagServer);
    room = joinedRoom(DirectoryTestClient(script), id: roomId);
    tags = MatrixRoomTags(room);
  });

  test('low priority is toggled with PUT and DELETE', () async {
    expect(tags.isLowPriority, isFalse);
    await tags.setLowPriority(true);
    setTags(room, {'m.lowpriority': <String, Object?>{}});
    expect(tags.isLowPriority, isTrue);
    await tags.setLowPriority(false);

    expect(calls(script), ['PUT m.lowpriority', 'DELETE m.lowpriority']);
    expect(script.seen.first.body, <String, Object?>{});
  });

  test('a custom tag is added and removed', () async {
    await tags.addCustomTag('u.custom');
    setTags(room, {
      'u.custom': <String, Object?>{},
      'm.favourite': <String, Object?>{},
      'u.another': <String, Object?>{},
    });
    expect(tags.customTags, ['u.another', 'u.custom']);
    await tags.removeCustomTag('u.custom');

    expect(calls(script), ['PUT u.custom', 'DELETE u.custom']);
  });

  test('a typed name becomes a u.* tag', () {
    expect(MatrixRoomTags.customTagFor('custom'), 'u.custom');
    expect(MatrixRoomTags.customTagFor('  u.custom '), 'u.custom');
    expect(MatrixRoomTags.customTagFor('m.work'), 'u.m.work',
        reason: 'what is typed is the name; the namespace is ours');
  });

  for (final invalid in [
    '',
    '   ',
    'u.',
    'custom',
    'm.custom',
    'm.lowpriority',
    'org.example.tag',
    ' u.custom',
    'u.${'x' * 254}',
  ]) {
    test(
        'refuses "${invalid.length > 20 ? '${invalid.substring(0, 20)}…' : invalid}"',
        () async {
      expect(() => tags.addCustomTag(invalid), throwsA(isA<InvalidRoomTag>()));
      expect(
          () => tags.removeCustomTag(invalid), throwsA(isA<InvalidRoomTag>()));
      expect(script.seen, isEmpty);
    });
  }

  test('an empty name is refused', () {
    for (final name in ['', '   ', 'u.', ' u. ']) {
      expect(() => MatrixRoomTags.customTagFor(name),
          throwsA(isA<InvalidRoomTag>()));
    }
    // The longest tag the spec allows (255 bytes) still goes.
    expect(MatrixRoomTags.isValidCustomTag('u.${'x' * 253}'), isTrue);
  });

  group('RoomTagsEditor', () {
    setUpAll(prepareTests);

    testWidgets('adds a typed tag, refuses an empty one, removes one',
        (tester) async {
      setTags(room, {'u.old': <String, Object?>{}});
      await tester.pumpWidget(host(RoomTagsEditor(tags)));
      expect(find.text('old'), findsOneWidget);

      await tester.tap(find.byKey(RoomTagsEditor.addKey));
      await settle(tester);
      expect(find.text(RoomPanelActions.errorRoomTagInvalid), findsOneWidget);
      expect(script.seen, isEmpty);

      await tester.enterText(find.byKey(RoomTagsEditor.fieldKey), 'custom');
      await tester.tap(find.byKey(RoomTagsEditor.addKey));
      await settle(tester);
      expect(find.text(RoomPanelActions.errorRoomTagInvalid), findsNothing);
      expect(find.text('custom'), findsOneWidget);

      await tester
          .tap(find.byTooltip(RoomPanelActions.promptRoomRemoveTag('old')));
      await settle(tester);
      expect(find.text('old'), findsNothing);

      expect(calls(script), ['PUT u.custom', 'DELETE u.old']);
    });
  });
}
