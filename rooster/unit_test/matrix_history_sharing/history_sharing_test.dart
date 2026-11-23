import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/history_sharing/matrix_history_sharing.dart';
import 'package:rooster/ui/pages/settings/categories/room/security/matrix_room_history_sharing_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import '../device_verification/verify_device_layout.dart'
    show loadFontsAndLanguages, phoneScreen;

const _roomId = '!1234:fakeServer.notExisting';

class FakeHistorySharing implements HistorySharingController {
  @override
  HistorySharingState state;
  @override
  HistorySharingNotice? notice;
  final choices = <bool>[];
  final _changes = StreamController<void>.broadcast();

  FakeHistorySharing(this.state, {this.notice});

  @override
  Stream<void> get changes => _changes.stream;

  void changed() => _changes.add(null);

  @override
  Future<void> setShareOnInvite(bool on) async {
    choices.add(on);
    state = on ? HistorySharingState.on : HistorySharingState.off;
  }
}

Future<matrix.Client> fakeClient() async {
  final database = await matrix.MatrixSdkDatabase.init(
    'history_sharing',
    database: await databaseFactoryFfi.openDatabase(':memory:',
        options: OpenDatabaseOptions(singleInstance: false)),
    sqfliteFactory: databaseFactoryFfi,
  );
  final client = matrix.Client('history_sharing',
      httpClient: FakeMatrixApi(), database: database);
  FakeMatrixApi.client = client;
  await client.checkHomeserver(Uri.parse('https://fakeServer.notExisting'),
      checkWellKnown: false);
  await client.init(
    newToken: 'abcd',
    newUserID: '@test:fakeServer.notExisting',
    newHomeserver: client.homeserver,
    newDeviceName: 'test',
    newDeviceID: 'TESTDEVICE',
  );
  await client.abortSync();
  return client;
}

/// [client]'s room with [visibility] (none when null), encrypted or not,
/// and our own choice in its account data.
Future<matrix.Room> room(
  matrix.Client client, {
  String? visibility,
  bool encrypted = true,
  bool? shareOnInvite,
}) async {
  matrix.MatrixEvent state(String type, Map<String, Object?> content) =>
      matrix.MatrixEvent(
        type: type,
        content: content,
        stateKey: '',
        senderId: client.userID!,
        eventId: '\$$type',
        originServerTs: DateTime.now(),
      );
  await client.handleSync(matrix.SyncUpdate(
    nextBatch: 'b',
    rooms: matrix.RoomsUpdate(join: {
      _roomId: matrix.JoinedRoomUpdate(
        state: [
          if (encrypted)
            state(matrix.EventTypes.Encryption,
                {'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2}),
          if (visibility != null)
            state(matrix.EventTypes.HistoryVisibility,
                {'history_visibility': visibility}),
        ],
        accountData: [
          if (shareOnInvite != null)
            matrix.BasicEvent(
              type: MatrixHistorySharing.accountDataType,
              content: {'share_on_invite': shareOnInvite},
            ),
        ],
      ),
    }),
  ));
  final room = client.getRoomById(_roomId)!;
  await room.postLoad();
  return room;
}

void main() {
  setUpAll(loadFontsAndLanguages);
  tearDown(() => intl.Intl.defaultLocale = null);

  group('the room decides whether an invite shares history', () {
    late matrix.Client client;
    setUp(() async => client = await fakeClient());
    tearDown(() => client.dispose(closeDatabase: true));

    test('on by default where newcomers may read earlier messages', () async {
      for (final visibility in ['shared', 'invited', 'world_readable']) {
        expect(
            MatrixHistorySharing.stateOf(
                await room(client, visibility: visibility)),
            HistorySharingState.on,
            reason: visibility);
      }
    });

    test('kept to members with "joined" or no visibility at all', () async {
      expect(
          MatrixHistorySharing.stateOf(
              await room(client, visibility: 'joined')),
          HistorySharingState.keptToMembers);
      final none = await fakeClient();
      addTearDown(() => none.dispose(closeDatabase: true));
      expect(MatrixHistorySharing.stateOf(await room(none)),
          HistorySharingState.keptToMembers);
    });

    test('off when we turned it off, nothing when not encrypted', () async {
      expect(
          MatrixHistorySharing.stateOf(
              await room(client, visibility: 'shared', shareOnInvite: false)),
          HistorySharingState.off);
      final plain = await fakeClient();
      addTearDown(() => plain.dispose(closeDatabase: true));
      expect(
          MatrixHistorySharing.stateOf(
              await room(plain, visibility: 'shared', encrypted: false)),
          HistorySharingState.notEncrypted);
    });

    test('the switch keeps our choice in the room\'s account data', () async {
      final r = await room(client, visibility: 'shared');
      await MatrixHistorySharing(r).setShareOnInvite(false);
      expect(
          FakeMatrixApi.calledEndpoints.keys.any((k) =>
              k.contains('/rooms/${Uri.encodeComponent(_roomId)}/account_data/'
                  '${MatrixHistorySharing.accountDataType}')),
          isTrue);
      expect(MatrixHistorySharing.stateOf(r), HistorySharingState.off);
      await MatrixHistorySharing(r).setShareOnInvite(true);
      expect(MatrixHistorySharing.stateOf(r), HistorySharingState.on);
    });

    test('inviting goes through the room', () async {
      await room(client, visibility: 'joined');
      FakeMatrixApi.calledEndpoints.clear();
      await MatrixHistorySharing.invite(client, _roomId, '@alice:example.com');
      expect(
          FakeMatrixApi.calledEndpoints.keys
              .where((k) => k.endsWith('/invite')),
          ['/client/v3/rooms/${Uri.encodeComponent(_roomId)}/invite']);
      expect(
          FakeMatrixApi.calledEndpoints.keys.where(
              (k) => k.contains('/media/') || k.contains('sendToDevice')),
          isEmpty);
    });
  });

  group('the security settings panel', () {
    Future<FakeHistorySharing> pump(
      WidgetTester tester,
      HistorySharingState state, {
      HistorySharingNotice? notice,
    }) async {
      final controller = FakeHistorySharing(state, notice: notice);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatrixRoomHistorySharingSettings(controller),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return controller;
    }

    bool switchedOn(WidgetTester tester) =>
        tester.widget<tiamat.Switch>(find.byType(tiamat.Switch)).state;

    testWidgets('turns sharing off and on', (tester) async {
      final controller = await pump(tester, HistorySharingState.on);
      expect(
          find.text(MatrixRoomHistorySharingSettings.labelHistorySharingToggle),
          findsOneWidget);
      expect(
          find.text(MatrixRoomHistorySharingSettings.messageHistorySharingOn),
          findsOneWidget);
      expect(switchedOn(tester), isTrue);

      await tester.tap(find.byType(tiamat.Switch));
      await tester.pumpAndSettle();
      expect(controller.choices, [false]);
      expect(switchedOn(tester), isFalse);
      expect(
          find.text(MatrixRoomHistorySharingSettings.messageHistorySharingOff),
          findsOneWidget);

      await tester.tap(find.byType(tiamat.Switch));
      await tester.pumpAndSettle();
      expect(controller.choices, [false, true]);
    });

    testWidgets('says why nothing is shared and cannot be switched on',
        (tester) async {
      final controller = await pump(tester, HistorySharingState.keptToMembers);
      expect(
          find.text(MatrixRoomHistorySharingSettings
              .messageHistorySharingKeptToMembers),
          findsOneWidget);
      expect(switchedOn(tester), isFalse);
      await tester.tap(find.byType(tiamat.Switch), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(controller.choices, isEmpty);
    });

    testWidgets('is not shown in a room without encryption', (tester) async {
      await pump(tester, HistorySharingState.notEncrypted);
      expect(find.byType(tiamat.Switch), findsNothing);
      expect(
          find.text(MatrixRoomHistorySharingSettings.labelHistorySharingHeader),
          findsNothing);
    });

    testWidgets('quietly notes history someone shared with us', (tester) async {
      final controller = await pump(tester, HistorySharingState.on);
      final note =
          MatrixRoomHistorySharingSettings.messageHistorySharingImported('Ana');
      expect(find.text(note), findsNothing);
      controller.notice =
          const HistorySharingNotice(senderName: 'Ana', keys: 3);
      controller.changed();
      await tester.pumpAndSettle();
      expect(find.text(note), findsOneWidget);
    });

    testWidgets('speaks Portuguese and fits a phone', (tester) async {
      intl.Intl.defaultLocale = 'pt';
      phoneScreen(tester, 360);
      await pump(tester, HistorySharingState.keptToMembers,
          notice: const HistorySharingNotice(senderName: 'Ana', keys: 3));
      expect(find.text('Compartilhar mensagens anteriores ao convidar alguém'),
          findsOneWidget);
      expect(
          find.text('Ana compartilhou com você, no convite, as chaves das '
              'mensagens anteriores desta sala.'),
          findsOneWidget);
      // No text cut nor wider than its box.
      expect(tester.takeException(), isNull);
      final paragraphs =
          tester.renderObjectList<RenderParagraph>(find.byType(RichText));
      expect(paragraphs, isNotEmpty);
      for (final p in paragraphs) {
        expect(p.didExceedMaxLines, isFalse, reason: p.text.toPlainText());
        expect(p.size.width <= p.constraints.maxWidth + 0.5, isTrue,
            reason: p.text.toPlainText());
      }
    });
  });
}
