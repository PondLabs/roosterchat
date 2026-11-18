// In a private conversation, two messages from the other person showed
// right under one of ours with no header, as if we had written them, and
// our next messages under our own name. Reported with a screenshot; the
// conversation below has the same shape, with other words.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dm_harness.dart';

const _theirs = Line(them, 'did you see the release notes');
const _theirsAgain = Line(them, 'they look done');
const _ours = Line(me, 'not quite yet');
const _awayFirst = Line(them, 'should I review the open pull requests?');
const _awaySecond = Line(them, 'right now?');
const _answer = Line(me, 'I am fixing the direct messages first');
const _answerAgain = Line(me, 'I had forgotten they were broken');
const _answerLast = Line(me, 'and this part needs work too');

void main() {
  setUpAll(() async {
    await setUpDmHarness();
    await useAppFonts();
  });
  tearDown(() => lifecycle(AppLifecycleState.resumed));

  testWidgets(
      'their messages that came in while we were away keep their header '
      'once we answer and the "New messages" line goes', (tester) async {
    final dm = await Dm.open(tester, [_theirs, _theirsAgain, _ours]);
    await dm.show(tester);

    // The window behind others: theirs arrive unseen, the line above the
    // first.
    lifecycle(AppLifecycleState.inactive);
    dm.receive(_awayFirst);
    await tester.pump();
    dm.receive(_awaySecond);
    await settle(tester);
    expect(find.text('New messages'), findsOneWidget);
    expectHeaders(tester, dm, {
      _ours.body: true,
      _awayFirst.body: true,
      _awaySecond.body: false,
    });

    // Back at the window, we answer: the line goes.
    lifecycle(AppLifecycleState.resumed);
    await settle(tester);
    final answer = dm.send(_answer);
    await settle(tester);
    expect(find.text('New messages'), findsNothing);

    dm.confirm(answer);
    await settle(tester);
    dm.confirm(dm.send(_answerAgain));
    await settle(tester);
    dm.confirm(dm.send(_answerLast));
    await settle(tester);

    await dm.picture(tester, 'screenshot-case');
    expectHeaders(tester, dm, {
      _theirs.body: true,
      _theirsAgain.body: false,
      _ours.body: true,
      _awayFirst.body: true,
      _awaySecond.body: false,
      _answer.body: true,
      _answerAgain.body: false,
      _answerLast.body: false,
    });
    await dm.close(tester);
  });
}
