// A message built again with an index that is no longer its own (its
// parent built it before newer messages came in below) still works its
// header out at the place it is now: the index it was given when it is
// still right, else the one it last loaded at, else found by its id.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:rooster/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'dm_harness.dart';

const _theirs = Line(them, 'a message of theirs');
const _ours = Line(me, 'the message drawn');
const _oursBefore = Line(me, 'ours, put in before it');
const _theirsBelow = Line(them, 'theirs, in below');
const _oursBelow = Line(me, 'ours, in below');

void main() {
  setUpAll(setUpDmHarness);

  /// The message drawn by itself, at the index [given] returns
  /// each time its parent builds it.
  Future<void Function()> draw(
      WidgetTester tester, Dm dm, int Function() given) async {
    late StateSetter setParent;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          setParent = setState;
          return TimelineEventViewMessage(
              timeline: dm.timeline, initialIndex: given());
        }),
      ),
    ));
    return () => setParent(() {});
  }

  bool header(WidgetTester tester) => tester
      .widget<TimelineEventLayoutMessage>(
          find.byType(TimelineEventLayoutMessage))
      .showSender;

  /// Ours, then ours again just before it, and two newer below it: the
  /// message drawn moves from index 0 to 2, now under one of ours.
  void changeAround(Dm dm) {
    dm.insert(dm.indexOf(_theirs.body), dm.say(_oursBefore));
    dm.insert(0, dm.say(_theirsBelow));
    dm.insert(0, dm.say(_oursBelow));
    expect(dm.indexOf(_ours.body), 2);
  }

  testWidgets(
      'built again at its old index, which another message holds now, it '
      'is found by its id', (tester) async {
    final dm = await Dm.open(tester, [_theirs, _ours]);
    final rebuild = await draw(tester, dm, () => 0);
    expect(header(tester), isTrue, reason: 'under theirs');

    changeAround(dm);
    // Neither the index given nor the one it loaded at is its own now.
    rebuild();
    await tester.pump();

    expect(header(tester), isFalse, reason: 'under ours, a moment before');
    await dm.close(tester);
  });

  testWidgets(
      'built again at its old index after it was told its new one, it '
      'keeps the new one', (tester) async {
    final dm = await Dm.open(tester, [_theirs, _ours]);
    final rebuild = await draw(tester, dm, () => 0);
    changeAround(dm);
    // Told, as the timeline view tells a message that changed.
    final state = tester.state(find.byType(TimelineEventViewMessage))
        as TimelineEventViewWidget;
    state.update(2);
    await tester.pump();
    expect(header(tester), isFalse);

    rebuild();
    await tester.pump();

    expect(header(tester), isFalse, reason: 'under ours, a moment before');
    await dm.close(tester);
  });
}
