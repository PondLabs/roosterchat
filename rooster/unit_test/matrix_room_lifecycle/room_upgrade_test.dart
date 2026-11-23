// Criterion 2: the upgrade asks /v3/capabilities for the room versions,
// tells stable from unstable ones, sends additional_creators only to room
// version 12 and later, and refuses without the power to upgrade.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/room_lifecycle/matrix_room_lifecycle_component.dart';
import 'package:rooster/ui/pages/settings/categories/room/general/matrix_room_upgrade_settings.dart';

import 'fakes.dart';

Map<String, Object?> roomVersions() => {
      'm.room_versions': {
        'default': '11',
        'available': {
          '1': 'stable',
          '10': 'stable',
          '11': 'stable',
          '12': 'stable',
          'org.matrix.msc9999': 'unstable',
          '13': 'unstable',
        },
      },
    };

void main() {
  setUpAll(preparePreferences);

  test('versions come from /v3/capabilities, stable apart from unstable',
      () async {
    final server = FakeHomeserver(capabilities: roomVersions());
    final room = buildRoom(LifecycleTestClient(server),
        states: [powerLevels()], roomVersion: '10');

    final options =
        await MatrixRoomLifecycleComponent(room).loadUpgradeOptions();

    expect(
        server.where('GET', '/_matrix/client/v3/capabilities'), hasLength(1));
    expect(options.currentVersion, '10');
    expect(options.defaultVersion, '11');
    expect(options.stable.map((v) => v.version), ['12', '11', '10', '1']);
    expect(
        options.unstable.map((v) => v.version), ['13', 'org.matrix.msc9999']);
    expect(options.versions.first.stable, isTrue);
  });

  test('a server without m.room_versions offers nothing to upgrade to',
      () async {
    final server = FakeHomeserver();
    final room =
        buildRoom(LifecycleTestClient(server), states: [powerLevels()]);

    final options =
        await MatrixRoomLifecycleComponent(room).loadUpgradeOptions();

    expect(options.versions, isEmpty);
    expect(options.defaultVersion, isNull);
  });

  test('additional_creators is a room version 12+ thing', () {
    expect(MatrixRoomLifecycleComponent.supportsAdditionalCreators('12'), true);
    expect(MatrixRoomLifecycleComponent.supportsAdditionalCreators('13'), true);
    expect(
        MatrixRoomLifecycleComponent.supportsAdditionalCreators('11'), false);
    expect(MatrixRoomLifecycleComponent.supportsAdditionalCreators('1'), false);
    expect(
        MatrixRoomLifecycleComponent.supportsAdditionalCreators(
            'org.matrix.hydra.11'),
        false);
  });

  group('upgrade', () {
    test('to RV12 sends additional_creators, without ourselves or blanks',
        () async {
      final server = FakeHomeserver();
      final room =
          buildRoom(LifecycleTestClient(server), states: [powerLevels()]);

      final replacement = await MatrixRoomLifecycleComponent(room).upgrade('12',
          additionalCreators: [
            '@co:example.org',
            ' ',
            self,
            '@co:example.org'
          ]);

      expect(replacement, '!upgraded:example.org');
      final upgrade = server.where('POST', '/rooms/!room:example.org/upgrade');
      expect(upgrade.single.body, {
        'new_version': '12',
        'additional_creators': ['@co:example.org'],
      });
    });

    test('to RV11 leaves additional_creators out', () async {
      final server = FakeHomeserver();
      final room =
          buildRoom(LifecycleTestClient(server), states: [powerLevels()]);

      await MatrixRoomLifecycleComponent(room)
          .upgrade('11', additionalCreators: ['@co:example.org']);

      final body = server.where('POST', '/upgrade').single.body!;
      expect(body, {'new_version': '11'});
      expect(body.containsKey('additional_creators'), isFalse);
    });

    test('to an experimental version leaves additional_creators out', () async {
      final server = FakeHomeserver();
      final room =
          buildRoom(LifecycleTestClient(server), states: [powerLevels()]);

      await MatrixRoomLifecycleComponent(room).upgrade('org.matrix.msc9999',
          additionalCreators: ['@co:example.org']);

      expect(server.where('POST', '/upgrade').single.body,
          {'new_version': 'org.matrix.msc9999'});
    });

    test('to RV12 with nobody else sends no additional_creators', () async {
      final server = FakeHomeserver();
      final room =
          buildRoom(LifecycleTestClient(server), states: [powerLevels()]);

      await MatrixRoomLifecycleComponent(room).upgrade('12');

      expect(
          server.where('POST', '/upgrade').single.body, {'new_version': '12'});
    });

    test('without the power to send m.room.tombstone it is refused', () async {
      final server = FakeHomeserver();
      final room = buildRoom(LifecycleTestClient(server), states: [
        powerLevels(ownLevel: 50, extra: {
          'events': {matrix.EventTypes.RoomTombstone: 100},
        }),
      ]);
      final lifecycle = MatrixRoomLifecycleComponent(room);

      expect(lifecycle.canUpgrade, isFalse);
      await expectLater(
          lifecycle.upgrade('12'), throwsA(isA<RoomUpgradeNotPermitted>()));
      expect(server.where('POST', '/upgrade'), isEmpty);
    });

    test('suggests the other creators of an RV12 room', () {
      final server = FakeHomeserver();
      final client = LifecycleTestClient(server);
      final room = matrix.Room(
          id: '!rv12:example.org',
          client: client,
          membership: matrix.Membership.join);
      room.setState(matrix.Event(
        type: matrix.EventTypes.RoomCreate,
        stateKey: '',
        eventId: r'$create',
        senderId: self,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1),
        content: {
          'room_version': '12',
          'additional_creators': ['@co:example.org'],
        },
        room: room,
      ));

      expect(MatrixRoomLifecycleComponent(room).suggestedAdditionalCreators,
          ['@co:example.org']);
    });
  });

  group('MatrixRoomUpgradeSettings', () {
    testWidgets('without permission there is no upgrade button',
        (tester) async {
      final server = FakeHomeserver(capabilities: roomVersions());
      final room = buildRoom(LifecycleTestClient(server), states: [
        powerLevels(ownLevel: 0),
      ]);

      await tester.pumpWidget(host(MatrixRoomUpgradeSettings(room)));

      expect(
          find.byKey(MatrixRoomUpgradeSettings.upgradeButtonKey), findsNothing);
      expect(
          find.text(MatrixRoomUpgradeSettings.messageUpgradeRoomNoPermission),
          findsOneWidget);
      expect(server.seen, isEmpty);
    });

    testWidgets(
        'lists stable and experimental versions and upgrades to RV12 '
        'with additional creators', (tester) async {
      final server = FakeHomeserver(capabilities: roomVersions());
      final room = buildRoom(LifecycleTestClient(server),
          states: [powerLevels()], roomVersion: '10');

      await tester.pumpWidget(host(MatrixRoomUpgradeSettings(room)));
      expect(find.text(MatrixRoomUpgradeSettings.labelCurrentRoomVersion('10')),
          findsOneWidget);

      await tester.tap(find.byKey(MatrixRoomUpgradeSettings.upgradeButtonKey));
      await settle(tester);

      expect(server.where('GET', '/v3/capabilities'), hasLength(1));
      expect(find.text(MatrixRoomUpgradeSettings.labelStableRoomVersions),
          findsOneWidget);
      expect(find.text(MatrixRoomUpgradeSettings.labelUnstableRoomVersions),
          findsOneWidget);
      expect(
          find.text(
              MatrixRoomUpgradeSettings.labelDefaultRoomVersionOption('11')),
          findsOneWidget);
      // The default (11) is picked: no creators field before RV12.
      expect(find.byKey(MatrixRoomUpgradeSettings.additionalCreatorsFieldKey),
          findsNothing);

      await tapVisible(tester,
          find.text(MatrixRoomUpgradeSettings.labelRoomVersionOption('12')));
      await tester.pump();
      expect(find.byKey(MatrixRoomUpgradeSettings.additionalCreatorsFieldKey),
          findsOneWidget);
      await tester.ensureVisible(
          find.byKey(MatrixRoomUpgradeSettings.additionalCreatorsFieldKey));
      await tester.enterText(
          find.byKey(MatrixRoomUpgradeSettings.additionalCreatorsFieldKey),
          '@co:example.org, @other:example.org');

      await tapVisible(
          tester, find.byKey(MatrixRoomUpgradeSettings.confirmUpgradeKey));
      await settle(tester);

      expect(server.where('POST', '/upgrade').single.body, {
        'new_version': '12',
        'additional_creators': ['@co:example.org', '@other:example.org'],
      });
    });

    testWidgets('upgrading to the default RV11 sends no creators',
        (tester) async {
      final server = FakeHomeserver(capabilities: roomVersions());
      final room = buildRoom(LifecycleTestClient(server),
          states: [powerLevels()], roomVersion: '10');

      await tester.pumpWidget(host(MatrixRoomUpgradeSettings(room)));
      await tester.tap(find.byKey(MatrixRoomUpgradeSettings.upgradeButtonKey));
      await settle(tester);
      await tapVisible(
          tester, find.byKey(MatrixRoomUpgradeSettings.confirmUpgradeKey));
      await settle(tester);

      expect(
          server.where('POST', '/upgrade').single.body, {'new_version': '11'});
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
