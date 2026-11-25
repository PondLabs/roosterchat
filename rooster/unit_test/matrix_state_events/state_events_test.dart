// Criteria 1 and 2: each of the ten standard room state events has its own
// converter and its own timeline line, in English and in Brazilian
// Portuguese; redacted (`{}`) or malformed content gives a plain line and
// never an exception. The lines are generic rows, never messages, so they
// do not move the "New messages" line nor count as the room's last message.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_canonical_alias.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_guest_access.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_history_visibility.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_join_rules.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_room_avatar.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_room_encryption.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_room_name.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_room_topic.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_server_acl.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_state.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_third_party_invite.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_unknown.dart';
import 'package:rooster/client/timeline_events/timeline_event_generic.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_generic.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'harness.dart';

/// One state event: its content, the class it becomes and its line.
typedef Case = ({
  String type,
  Map<String, Object?> content,
  Map<String, Object?>? prev,
  Type converter,
  String en,
  String pt,
});

Case c(String type, Map<String, Object?> content, Type converter, String en,
        String pt, {Map<String, Object?>? prev}) =>
    (
      type: type,
      content: content,
      prev: prev,
      converter: converter,
      en: en,
      pt: pt
    );

const acl = 'm.room.server_acl';
const thirdPartyInvite = 'm.room.third_party_invite';

/// The ten types, each with content as a homeserver sends it.
final happy = <Case>[
  c(
      matrix.EventTypes.RoomName,
      {'name': 'The Coop'},
      MatrixTimelineEventRoomName,
      'Alice changed the room name to The Coop',
      'Alice mudou o nome da sala para The Coop'),
  c(
      matrix.EventTypes.RoomTopic,
      {'topic': 'Eggs every morning'},
      MatrixTimelineEventRoomTopic,
      'Alice changed the topic to: Eggs every morning',
      'Alice mudou a descrição para: Eggs every morning'),
  c(
      matrix.EventTypes.RoomAvatar,
      {'url': 'mxc://example.org/egg'},
      MatrixTimelineEventRoomAvatar,
      'Alice changed the room picture',
      'Alice mudou a imagem da sala'),
  c(
      matrix.EventTypes.Encryption,
      {'algorithm': 'm.megolm.v1.aes-sha2'},
      MatrixTimelineEventRoomEncryption,
      'Alice turned on end-to-end encryption',
      'Alice ativou a criptografia de ponta a ponta'),
  c(
      matrix.EventTypes.RoomJoinRules,
      {'join_rule': 'public'},
      MatrixTimelineEventJoinRules,
      'Alice made the room public: anyone can join',
      'Alice tornou a sala pública: qualquer pessoa pode entrar'),
  c(
      matrix.EventTypes.HistoryVisibility,
      {'history_visibility': 'joined'},
      MatrixTimelineEventHistoryVisibility,
      'Alice made new messages readable by members from the time they '
          'joined',
      'Alice deixou as novas mensagens visíveis para os membros a partir do '
          'momento em que entraram'),
  c(
      matrix.EventTypes.GuestAccess,
      {'guest_access': 'can_join'},
      MatrixTimelineEventGuestAccess,
      'Alice let guests join the room',
      'Alice permitiu que visitantes entrem na sala'),
  c(
      matrix.EventTypes.RoomCanonicalAlias,
      {
        'alias': '#coop:example.org',
        'alt_aliases': ['#hens:example.org'],
      },
      MatrixTimelineEventCanonicalAlias,
      'Alice set the main address of the room to #coop:example.org',
      'Alice definiu o endereço principal da sala como #coop:example.org'),
  c(
      acl,
      {
        'allow': ['*'],
        'deny': ['evil.example'],
        'allow_ip_literals': false,
      },
      MatrixTimelineEventServerAcl,
      'Alice changed which servers can take part in the room',
      'Alice mudou quais servidores podem participar da sala'),
  c(
      thirdPartyInvite,
      {
        'display_name': 'bob…@example.org',
        'key_validity_url': 'https://example.org/isvalid',
        'public_key': 'abc',
      },
      MatrixTimelineEventThirdPartyInvite,
      'Alice invited bob…@example.org to the room',
      'Alice convidou bob…@example.org para a sala'),
];

/// The other values each type can say, in English.
final variants = <Case>[
  for (final (rule, en) in [
    ('invite', 'Alice made the room invite only'),
    ('private', 'Alice made the room invite only'),
    ('knock', 'Alice let people ask to join the room'),
    ('restricted', 'Alice let members of certain spaces join the room'),
    (
      'knock_restricted',
      'Alice let members of certain spaces join the room, and others ask '
          'to join'
    ),
  ])
    c(matrix.EventTypes.RoomJoinRules, {'join_rule': rule},
        MatrixTimelineEventJoinRules, en, ''),
  for (final (visibility, en) in [
    (
      'shared',
      'Alice made new messages readable by every member, including those '
          'who join later'
    ),
    (
      'invited',
      'Alice made new messages readable by members from the time they were '
          'invited'
    ),
    ('world_readable', 'Alice made new messages readable by anyone'),
  ])
    c(matrix.EventTypes.HistoryVisibility, {'history_visibility': visibility},
        MatrixTimelineEventHistoryVisibility, en, ''),
  c(
      matrix.EventTypes.GuestAccess,
      {'guest_access': 'forbidden'},
      MatrixTimelineEventGuestAccess,
      'Alice stopped guests from joining the room',
      ''),
  c(matrix.EventTypes.RoomName, {'name': ''}, MatrixTimelineEventRoomName,
      'Alice removed the room name', ''),
  c(matrix.EventTypes.RoomTopic, {'topic': ''}, MatrixTimelineEventRoomTopic,
      'Alice removed the topic', ''),
  c(matrix.EventTypes.RoomAvatar, {}, MatrixTimelineEventRoomAvatar,
      'Alice removed the room picture', ''),
  c(matrix.EventTypes.RoomCanonicalAlias, {}, MatrixTimelineEventCanonicalAlias,
      'Alice removed the main address of the room', '',
      prev: {'alias': '#coop:example.org'}),
  c(
      matrix.EventTypes.RoomCanonicalAlias,
      {
        'alias': '#coop:example.org',
        'alt_aliases': ['#hens:example.org'],
      },
      MatrixTimelineEventCanonicalAlias,
      'Alice changed the other addresses of the room',
      '',
      prev: {'alias': '#coop:example.org'}),
  c(
      matrix.EventTypes.RoomCanonicalAlias,
      {
        'alt_aliases': ['#hens:example.org'],
      },
      MatrixTimelineEventCanonicalAlias,
      'Alice changed the other addresses of the room',
      ''),
  c(thirdPartyInvite, {}, MatrixTimelineEventThirdPartyInvite,
      'Alice revoked the invitation for bob…@example.org', '',
      prev: {'display_name': 'bob…@example.org'}),
];

/// Redacted (`{}`) and malformed content, with the plain line it gives.
final broken = <Case>[
  for (final content in <Map<String, Object?>>[
    {},
    {'name': 42},
    {'name': '   '},
    {
      'name': ['x']
    },
  ])
    c(matrix.EventTypes.RoomName, content, MatrixTimelineEventRoomName,
        'Alice removed the room name', 'Alice removeu o nome da sala'),
  for (final content in <Map<String, Object?>>[
    {},
    {'topic': 42},
    {'topic': null, 'm.topic': 'not a map'},
    {
      'm.topic': {'m.text': 'not a list'}
    },
    {
      'm.topic': {
        'm.text': [
          1,
          {'body': 2},
          {'body': 'x', 'mimetype': 5},
          {'body': '  ', 'mimetype': 'text/html'},
        ]
      }
    },
  ])
    c(matrix.EventTypes.RoomTopic, content, MatrixTimelineEventRoomTopic,
        'Alice removed the topic', 'Alice removeu a descrição'),
  for (final content in <Map<String, Object?>>[
    {},
    {'url': 42},
    {'url': null},
  ])
    c(matrix.EventTypes.RoomAvatar, content, MatrixTimelineEventRoomAvatar,
        'Alice removed the room picture', 'Alice removeu a imagem da sala'),
  for (final content in <Map<String, Object?>>[
    {},
    {'algorithm': null},
    {'algorithm': 7},
    {'algorithm': 'm.unknown.algorithm'},
  ])
    c(
        matrix.EventTypes.Encryption,
        content,
        MatrixTimelineEventRoomEncryption,
        'Alice changed the encryption settings',
        'Alice mudou as configurações de criptografia'),
  for (final content in <Map<String, Object?>>[
    {},
    {'join_rule': 7},
    {'join_rule': 'open_sesame'},
    {'join_rule': null, 'allow': 'not a list'},
  ])
    c(
        matrix.EventTypes.RoomJoinRules,
        content,
        MatrixTimelineEventJoinRules,
        'Alice changed who can join the room',
        'Alice mudou quem pode entrar na sala'),
  for (final content in <Map<String, Object?>>[
    {},
    {'history_visibility': {}},
    {'history_visibility': 'forever'},
  ])
    c(
        matrix.EventTypes.HistoryVisibility,
        content,
        MatrixTimelineEventHistoryVisibility,
        'Alice changed who can read the room history',
        'Alice mudou quem pode ler o histórico da sala'),
  for (final content in <Map<String, Object?>>[
    {},
    {'guest_access': true},
    {'guest_access': 'maybe'},
  ])
    c(
        matrix.EventTypes.GuestAccess,
        content,
        MatrixTimelineEventGuestAccess,
        'Alice changed guest access to the room',
        'Alice mudou o acesso de visitantes à sala'),
  for (final content in <Map<String, Object?>>[
    {},
    {'alias': 3, 'alt_aliases': 'x'},
    {'alias': 'not-an-address'},
  ])
    c(
        matrix.EventTypes.RoomCanonicalAlias,
        content,
        MatrixTimelineEventCanonicalAlias,
        'Alice removed the main address of the room',
        'Alice removeu o endereço principal da sala'),
  for (final content in <Map<String, Object?>>[
    {},
    {'allow': 'x', 'deny': 5, 'allow_ip_literals': 'no'},
  ])
    c(
        acl,
        content,
        MatrixTimelineEventServerAcl,
        'Alice changed which servers can take part in the room',
        'Alice mudou quais servidores podem participar da sala'),
  for (final content in <Map<String, Object?>>[
    {},
    {'display_name': 9},
    {'display_name': ''},
  ])
    c(thirdPartyInvite, content, MatrixTimelineEventThirdPartyInvite,
        'Alice revoked an invitation', 'Alice cancelou um convite'),
];

void main() {
  late MatrixClient client;
  late MatrixRoom room;

  setUpAll(() async {
    sqfliteFfiInit();
    (client, room) = await stateEventsRoom('state_events');
  });

  tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

  Future<void> pumpLine(WidgetTester tester, Case event) async {
    final converted =
        convert(room, event.type, event.content, prevContent: event.prev);
    await tester.pumpWidget(host(TimelineEventViewGeneric(
      initialEvent: converted,
      initialIndex: 0,
      room: room,
    )));
  }

  test('every standard state type has a converter of its own', () {
    expect(happy.map((e) => e.type).toSet(), hasLength(10));
    expect(happy.map((e) => e.converter).toSet(), hasLength(10));
    for (final event in happy) {
      final converted = convert(room, event.type, event.content);
      expect(converted.runtimeType, event.converter, reason: event.type);
      expect(converted, isA<MatrixTimelineEventState>());
    }
  });

  group('lines in English', () {
    for (final event in [...happy, ...variants]) {
      test('${event.type} ${event.content} → ${event.en}', () {
        final converted =
            convert(room, event.type, event.content, prevContent: event.prev)
                as TimelineEventGeneric;
        expect(converted.runtimeType, event.converter);
        expect(converted.getBody(), event.en);
        expect(converted.plainTextBody, event.en);
        expect(converted.icon, isNotNull);
        expect(converted.showSenderAvatar, isFalse);
      });
    }
  });

  for (final locale in ['en', 'pt']) {
    group('timeline rows ($locale)', () {
      for (final event in happy) {
        testWidgets(event.type, (tester) async {
          await useLocale(locale);
          await pumpLine(tester, event);
          expect(
              find.text(locale == 'en' ? event.en : event.pt), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    });

    group('redacted or malformed content ($locale)', () {
      for (final event in broken) {
        testWidgets('${event.type} ${event.content}', (tester) async {
          await useLocale(locale);
          final converted =
              convert(room, event.type, event.content) as TimelineEventGeneric;
          expect(converted.runtimeType, event.converter);
          final line = locale == 'en' ? event.en : event.pt;
          expect(converted.getBody(), line);

          await pumpLine(tester, event);
          expect(find.text(line), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    });
  }

  test('a redacted state event is converted without an exception', () {
    for (final event in happy) {
      final redacted =
          room.convertEvent(stateEvent(room, event.type, {}, unsigned: {
        'redacted_because': {
          'type': matrix.EventTypes.Redaction,
          'sender': alice,
          'event_id': r'$redaction',
          'origin_server_ts': 2000,
          'content': {},
        },
      }));
      expect(redacted, isA<MatrixTimelineEventUnknown>(), reason: event.type);
      expect(() => redacted.plainTextBody, returnsNormally);
    }
  });

  test(
      'the rows are generic, not messages: they do not move the '
      '"New messages" line', () {
    for (final event in [...happy, ...broken]) {
      final converted = convert(room, event.type, event.content);
      expect(TimelineViewEntryState.eventToDisplayType(converted),
          TimelineEventWidgetDisplayType.generic,
          reason: event.type);
    }
  });
}
