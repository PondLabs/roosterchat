// The activity shelf: the entries it renders, and the actions firing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/ui/organisms/call_activity/activity_picker_panel.dart';

/// One real entry shaped like the one the game registers at boot (its
/// title is a proper name, not translated).
const sunnySidePutt = CallActivity(
  id: 'chat.commet.putt',
  displayName: _sunnySidePuttName,
);

String _sunnySidePuttName() => 'Sunny Side Putt';

void main() {
  group('ActivityPickerPanel', () {
    testWidgets('renders the registry entries with a Launch each',
        (tester) async {
      await tester.pumpWidget(_wrap(ActivityPickerPanel(
        activities: const [sunnySidePutt],
        liveSessions: const [],
        nameOf: (id) => id,
      )));

      expect(find.text('Sunny Side Putt'), findsOneWidget);
      expect(find.text('Launch'), findsOneWidget);
    });

    testWidgets('the Launch action fires with the activity', (tester) async {
      CallActivity? launched;
      await tester.pumpWidget(_wrap(ActivityPickerPanel(
        activities: const [sunnySidePutt],
        liveSessions: const [],
        nameOf: (id) => id,
        onLaunch: (activity) => launched = activity,
      )));

      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();

      expect(launched, same(sunnySidePutt));
    });

    testWidgets('a running session shows who started it and a Join',
        (tester) async {
      ActivitySessionEntry? joined;
      await tester.pumpWidget(_wrap(ActivityPickerPanel(
        activities: const [sunnySidePutt],
        liveSessions: const [
          (
            sessionId: 'session-1',
            activityId: 'chat.commet.putt',
            hostUserId: '@host:example.org',
          ),
        ],
        nameOf: (id) => 'Host',
        onJoin: (entry) => joined = entry,
      )));

      expect(find.text('Host started Sunny Side Putt'), findsOneWidget);
      // A session of it runs: the shelf offers Join, not another Launch.
      expect(find.text('Launch'), findsNothing);

      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(joined?.sessionId, 'session-1');
      expect(joined?.activityId, 'chat.commet.putt');
    });

    testWidgets('an empty shelf says there is nothing to play', (tester) async {
      await tester.pumpWidget(_wrap(ActivityPickerPanel(
        activities: const [],
        liveSessions: const [],
        nameOf: (id) => id,
      )));

      expect(find.text('No activities to play yet.'), findsOneWidget);
    });
  });
}

/// Text direction and material scaffolding around the panel under test.
Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
