import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_capabilities_manager.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_permission_groups.dart';

import 'widget_fakes.dart';

const navigate = 'org.matrix.msc2931.navigate';
const receiveMessages = 'org.matrix.msc2762.receive.event:m.room.message';
const userDirectory = 'org.matrix.msc3973.user_directory_search';
const alwaysOnScreen = 'm.always_on_screen';
const sendSticky = 'org.matrix.msc4407.send.sticky_event';
const receiveSticky = 'org.matrix.msc4407.receive.sticky_event';
const sendMember =
    'org.matrix.msc2762.send.event:org.matrix.msc4143.rtc.member';

const realCapabilities = [
  navigate,
  receiveMessages,
  userDirectory,
  alwaysOnScreen,
  sendSticky,
  receiveSticky,
];

final navigateRequest = fromWidget(navigate, {
  'uri': 'https://matrix.to/#/!room:localhost',
});
final searchRequest = fromWidget(userDirectory, {'search_term': 'ali'});
final alwaysOnScreenRequest =
    fromWidget('set_always_on_screen', {'value': true});
final readRequest = fromWidget('org.matrix.msc2876.read_events', {
  'type': 'm.room.message',
});
final stickyRequest = fromWidget('send_event', {
  'type': 'org.matrix.msc4143.rtc.member',
  'content': {'application': 'm.call'},
  'sticky_duration_ms': 3600000,
});

void main() {
  test('every real capability is asked of the user, none is a default', () {
    for (final capability in realCapabilities) {
      expect(MatrixWidgetCapabilitiesManager.defaultCapabilities,
          isNot(contains(capability)));
      expect(MatrixWidgetCapabilitiesManager.canCreateCapability(capability),
          isTrue,
          reason: '$capability must be one Rooster can grant');
    }
  });

  test('the capabilities go to the permission dialog before being granted',
      () async {
    final built = buildManager(answer: (asked) => asked);

    final granted =
        await built.runner.manager.requestCapabilities(realCapabilities);

    expect(built.prompt.asked.single, containsAll(realCapabilities));
    expect(granted, containsAll(realCapabilities));
  });

  test('navigate, open rooms and user search start unticked in the dialog', () {
    final groups = MatrixWidgetPermissionGroup.groupPermissions(
        [navigate, alwaysOnScreen, userDirectory]).$1;

    expect(groups.map((i) => i.defaultValue), everyElement(isFalse));
    expect(groups.expand((i) => i.permissions).map((i) => i.raw),
        containsAll([navigate, alwaysOnScreen, userDirectory]));
  });

  group('without permission', () {
    Future<void> expectDenied(
        ({
          FakeRunner runner,
          RecordingHostActions actions,
          RecordingPrompt prompt
        }) built) async {
      final manager = built.runner.manager;
      for (final (request, capability) in [
        (navigateRequest, navigate),
        (searchRequest, userDirectory),
        (alwaysOnScreenRequest, alwaysOnScreen),
        (readRequest, receiveMessages),
        (stickyRequest, sendSticky),
      ]) {
        final reply = await manager.handleEvent(request);
        expect(errorOf(reply),
            'Permission denied: missing capability $capability');
      }
      expect(built.actions.ranAnything, isFalse);
      expect(manager.alwaysOnScreen.value, isFalse);
    }

    test('a widget that never asked is refused and nothing runs', () async {
      final built = buildManager(room: FakeRoom());
      await expectDenied(built);
    });

    test('a dismissed dialog grants nothing', () async {
      final built = buildManager(room: FakeRoom(), answer: (_) => null);
      final granted = await built.runner.manager
          .requestCapabilities([...realCapabilities, sendMember]);

      // Only the harmless defaults, which every widget gets.
      expect(
          granted,
          everyElement(
              isIn(MatrixWidgetCapabilitiesManager.defaultCapabilities)));
      await expectDenied(built);
    });

    test('capabilities the user unticks stay refused', () async {
      final built = buildManager(room: FakeRoom(), answer: (_) => const []);
      await built.runner.manager.requestCapabilities(realCapabilities);

      await expectDenied(built);
    });

    test('a sticky event needs the sticky capability, not only its type',
        () async {
      final built =
          buildManager(room: FakeRoom(), answer: (_) => const [sendMember]);
      await built.runner.manager.requestCapabilities([sendMember, sendSticky]);

      final reply = await built.runner.manager.handleEvent(stickyRequest);

      expect(
          errorOf(reply), 'Permission denied: missing capability $sendSticky');
      expect(built.actions.stickySent, isEmpty);
    });

    test('send.event alone does not send a sticky event as a plain one',
        () async {
      // The sticky capability was never asked for, so it is not refused
      // either: only the send.event capability could take the request.
      final built = buildManager(room: FakeRoom());
      await built.runner.manager.requestCapabilities([sendMember]);

      final reply = await built.runner.manager.handleEvent(stickyRequest);

      expect(
          errorOf(reply), 'Permission denied: missing capability $sendSticky');
    });

    test('a sticky event needs the send capability for its type', () async {
      final built =
          buildManager(room: FakeRoom(), answer: (_) => const [sendSticky]);
      await built.runner.manager.requestCapabilities([sendSticky]);

      final reply = await built.runner.manager.handleEvent(stickyRequest);

      expect(
          errorOf(reply), 'Permission denied: missing capability $sendSticky');
      expect(built.actions.stickySent, isEmpty);
    });
  });

  group('with permission', () {
    test('navigate opens a matrix.to link', () async {
      final built = buildManager();
      await built.runner.manager.requestCapabilities([navigate]);

      final reply = await built.runner.manager.handleEvent(navigateRequest);

      expect(errorOf(reply), isNull);
      expect(built.actions.navigated,
          [Uri.parse('https://matrix.to/#/!room:localhost')]);
    });

    test('navigate refuses any other link', () async {
      final built = buildManager();
      await built.runner.manager.requestCapabilities([navigate]);

      for (final uri in [
        'https://example.com/#/!room:localhost',
        'http://matrix.to/#/!room:localhost',
        'javascript:alert(1)',
      ]) {
        final reply = await built.runner.manager
            .handleEvent(fromWidget(navigate, {'uri': uri}));
        expect(errorOf(reply), 'Invalid matrix.to URI');
      }
      expect(built.actions.navigated, isEmpty);
    });

    test('user directory search answers as MSC3973 says', () async {
      final built = buildManager();
      await built.runner.manager.requestCapabilities([userDirectory]);

      final reply = await built.runner.manager.handleEvent(searchRequest);

      expect(built.actions.searched, ['ali']);
      expect(reply.response, {
        'limited': false,
        'results': [
          {
            'user_id': '@alice:localhost',
            'display_name': 'Alice',
            'avatar_url': 'mxc://localhost/alice',
          },
        ],
      });
    });

    test('always on screen is kept until the widget closes', () async {
      final built = buildManager();
      await built.runner.manager.requestCapabilities([alwaysOnScreen]);

      final reply =
          await built.runner.manager.handleEvent(alwaysOnScreenRequest);

      expect(reply.response, {'success': true});
      expect(built.runner.manager.alwaysOnScreen.value, isTrue);

      built.runner.manager.dispose();
      expect(built.runner.manager.alwaysOnScreen.value, isFalse);
    });

    test('a sticky event is sent with both capabilities', () async {
      final built = buildManager(room: FakeRoom());
      await built.runner.manager.requestCapabilities([sendMember, sendSticky]);

      final reply = await built.runner.manager.handleEvent(stickyRequest);

      expect(reply.response,
          {'room_id': '!room:localhost', 'event_id': '\$sticky'});
      expect(built.actions.stickySent.single.durationMs, 3600000);
      expect(built.actions.stickySent.single.type,
          'org.matrix.msc4143.rtc.member');
    });

    test('a granted receive capability lets read_events through', () async {
      final built = buildManager(room: FakeRoom());
      await built.runner.manager.requestCapabilities([receiveMessages]);

      final handler = built.runner.manager.grantedCapabilities[receiveMessages];
      expect(handler?.canHandleRequest(readRequest), isTrue);
    });
  });
}
