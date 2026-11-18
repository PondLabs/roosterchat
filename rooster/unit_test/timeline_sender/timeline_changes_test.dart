// A message's header (its sender's name and avatar) follows the message
// before it as the timeline changes under a message already drawn: shown
// when that message is someone else's, left out under one by the same
// person a moment before. Each change below is one the Matrix SDK makes
// to an open timeline.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'dm_harness.dart';

const _first = Line(them, 'first of theirs');
const _second = Line(them, 'second of theirs');
const _third = Line(them, 'third of theirs');
const _ours = Line(me, 'one of ours');
const _oursAgain = Line(me, 'another of ours');

void main() {
  setUpAll(setUpDmHarness);
  tearDown(() => lifecycle(AppLifecycleState.resumed));

  testWidgets(
      'our pending message, taken by the server and put back between two '
      'of theirs, splits them', (tester) async {
    final dm = await Dm.open(tester, [_first, _second, _third]);
    await dm.show(tester);
    final txn = dm.send(_ours);
    await settle(tester);
    expectHeaders(tester, dm, {
      _first.body: true,
      _second.body: false,
      _third.body: false,
      _ours.body: true,
    });

    // The server has it before their second: out of the bottom, back in
    // between their first and second.
    final echo = dm.sdk.events[dm.indexOf(_ours.body)];
    dm.remove(dm.indexOf(_ours.body));
    dm.insert(
        dm.indexOf(_first.body),
        dm.message(me, _ours.body,
            id: '\$sent-$txn',
            at: echo.originServerTs,
            status: matrix.EventStatus.synced,
            transactionId: txn));
    await settle(tester);

    expectHeaders(tester, dm, {
      _first.body: true,
      _ours.body: true,
      _second.body: true,
      _third.body: false,
    });
    await dm.close(tester);
  });

  testWidgets(
      'local echoes replaced by their events, one while their message comes '
      'in, keep the header right', (tester) async {
    final dm = await Dm.open(tester, [_first]);
    await dm.show(tester);
    final one = dm.send(_ours);
    final another = dm.send(_oursAgain);
    await settle(tester);
    expectHeaders(tester, dm, {
      _first.body: true,
      _ours.body: true,
      _oursAgain.body: false,
    });

    // The server takes the first; theirs comes in before the change is
    // heard, then the second is taken.
    dm.confirm(one);
    dm.receive(_second);
    await settle(tester);
    dm.confirm(another);
    await settle(tester);

    expectHeaders(tester, dm, {
      _first.body: true,
      _ours.body: true,
      _oursAgain.body: false,
      _second.body: true,
    });
    await dm.close(tester);
  });

  testWidgets(
      'their messages decrypted after ours came in under them get their '
      'header, and the second stays under the first', (tester) async {
    final dm = await Dm.open(tester, [_ours]);
    await dm.show(tester);
    final first = dm.receiveSealed(_first);
    final second = dm.receiveSealed(_second);
    await settle(tester);
    dm.confirm(dm.send(_oursAgain));
    await settle(tester);

    dm.decrypt(first);
    await settle(tester);
    dm.decrypt(second);
    await settle(tester);

    expectHeaders(tester, dm, {
      _ours.body: true,
      _first.body: true,
      _second.body: false,
      _oursAgain.body: true,
    });
    await dm.close(tester);
  });

  testWidgets(
      'a message put in between two of theirs, already drawn, splits them',
      (tester) async {
    final dm = await Dm.open(tester, [_first, _second]);
    await dm.show(tester);
    // More of theirs below, so the two are not the newest any more.
    dm.receive(_third);
    await settle(tester);
    expectHeaders(tester, dm, {
      _first.body: true,
      _second.body: false,
      _third.body: false,
    });

    dm.insert(dm.indexOf(_first.body), dm.say(_ours));
    await settle(tester);

    expectHeaders(tester, dm, {
      _first.body: true,
      _ours.body: true,
      _second.body: true,
      _third.body: false,
    });
    await dm.close(tester);
  });

  testWidgets(
      'when the message before one goes (a send cancelled), the one after '
      'follows the message now before it', (tester) async {
    final dm = await Dm.open(tester, [_first]);
    await dm.show(tester);
    dm.send(_ours);
    dm.confirm(dm.send(_oursAgain));
    await settle(tester);
    expectHeaders(tester, dm, {
      _first.body: true,
      _ours.body: true,
      _oursAgain.body: false,
    });

    // The first of ours, still sending, cancelled: theirs is now the one
    // before the second.
    dm.remove(dm.indexOf(_ours.body));
    await settle(tester);
    expect(find.text(_ours.body, findRichText: true), findsNothing);

    expectHeaders(tester, dm, {
      _first.body: true,
      _oursAgain.body: true,
    });
    await dm.close(tester);
  });

  testWidgets(
      'when the message before one is redacted, the one after shows its '
      'header', (tester) async {
    final dm = await Dm.open(tester, [_first, _ours, _oursAgain]);
    await dm.show(tester);
    dm.receive(_second);
    await settle(tester);
    expectHeaders(tester, dm, {
      _ours.body: true,
      _oursAgain.body: false,
      _second.body: true,
    });

    dm.redact(_ours.body);
    await settle(tester);

    expectHeaders(tester, dm, {
      _first.body: true,
      _oursAgain.body: true,
      _second.body: true,
    });
    await dm.close(tester);
  });

  testWidgets(
      'new messages below: a header at each change of sender, none under '
      'the same sender', (tester) async {
    final dm = await Dm.open(tester, [_first]);
    await dm.show(tester);

    dm.confirm(dm.send(_ours));
    await settle(tester);
    dm.confirm(dm.send(_oursAgain));
    await settle(tester);
    dm.receive(_second);
    await settle(tester);
    dm.receive(_third);
    await settle(tester);

    expectHeaders(tester, dm, {
      _first.body: true,
      _ours.body: true,
      _oursAgain.body: false,
      _second.body: true,
      _third.body: false,
    });
    await dm.close(tester);
  });

  testWidgets(
      'through every change, each message carries the name and avatar of '
      'its own sender, never those of a neighbour', (tester) async {
    final dm = await Dm.open(tester, [_first, _ours]);
    await dm.show(tester);
    final steps = <String, void Function()>{
      'theirs in, encrypted': () => dm.receiveSealed(_second),
      'ours sent': () => dm.send(_oursAgain),
      'theirs decrypted': () => dm.decrypt(dm.sdk.events[1].eventId),
      'ours taken': () => dm.confirm(dm.sdk.events[0].eventId),
      'theirs in the middle': () =>
          dm.insert(dm.indexOf(_ours.body), dm.say(_third)),
      'ours redacted': () => dm.redact(_ours.body),
    };
    for (final step in steps.entries) {
      step.value();
      await settle(tester);
      expectOwnNames(tester, dm);
    }
    // Their first, ours (redacted, so not drawn), their third and second,
    // our other: their third sits right under their first.
    expectHeaders(tester, dm, {
      _first.body: true,
      _third.body: false,
      _second.body: false,
      _oursAgain.body: true,
    });
    await dm.close(tester);
  });
}
