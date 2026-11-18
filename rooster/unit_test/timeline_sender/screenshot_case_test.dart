// In a private conversation, two messages from the other person showed
// right under one of ours with no header, as if we had written them. Asked
// for with a screenshot: apbianco's "bah eh pra mexer nos prs do rooster?"
// and "agorinha?" under the owner's "its over", then the owner's next
// three messages under their own name.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dm_harness.dart';

const _reply = Line(them, 'cade meu fellow its over ite');
const _itsoverist = Line(them, 'itsoverist');
const _itsOver = Line(me, 'its over');
const _bah = Line(them, 'bah eh pra mexer nos prs do rooster?');
const _agorinha = Line(them, 'agorinha?');
const _fixing = Line(me, 'Estou arrumando as DMs dessa bosta');
const _forgot = Line(me, 'tinha até esquecido que estava quebrado');
const _broken = Line(me, 'e isso aqui tá podre também]');

void main() {
  setUpAll(() async {
    await setUpDmHarness();
    await useAppFonts();
  });
  tearDown(() => lifecycle(AppLifecycleState.resumed));

  testWidgets(
      'their messages that came in while we were away keep their header '
      'once we answer and the "New messages" line goes', (tester) async {
    final dm = await Dm.open(tester, [_reply, _itsoverist, _itsOver]);
    await dm.show(tester);

    // The window behind others: theirs arrive unseen, the line above the
    // first.
    lifecycle(AppLifecycleState.inactive);
    dm.receive(_bah);
    await tester.pump();
    dm.receive(_agorinha);
    await settle(tester);
    expect(find.text('New messages'), findsOneWidget);
    expectHeaders(tester, dm, {
      _itsOver.body: true,
      _bah.body: true,
      _agorinha.body: false,
    });

    // Back at the window, we answer: the line goes.
    lifecycle(AppLifecycleState.resumed);
    await settle(tester);
    final fixing = dm.send(_fixing);
    await settle(tester);
    expect(find.text('New messages'), findsNothing);

    dm.confirm(fixing);
    await settle(tester);
    dm.confirm(dm.send(_forgot));
    await settle(tester);
    dm.confirm(dm.send(_broken));
    await settle(tester);

    await dm.picture(tester, 'conversa-do-print');
    expectHeaders(tester, dm, {
      _reply.body: true,
      _itsoverist.body: false,
      _itsOver.body: true,
      _bah.body: true,
      _agorinha.body: false,
      _fixing.body: true,
      _forgot.body: false,
      _broken.body: false,
    });
    await dm.close(tester);
  });
}
