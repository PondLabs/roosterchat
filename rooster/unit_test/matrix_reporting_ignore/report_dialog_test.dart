// Criterion 1: the report dialog sends the reason typed (or none), says
// when the report went through, and shows the server's refusal in the
// app's language.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/matrix/components/reporting/matrix_content_reports.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/organisms/moderation/report_content_dialog.dart';

import 'fakes.dart';

const roomId = '!room:example.org';
const eventId = r'$event:example.org';

/// Opens the dialog for a message, the server answering with [answer].
Future<Script> openDialog(WidgetTester tester,
    {http.Response Function()? answer,
    ReportTarget target = ReportTarget.message}) async {
  final script = Script()
    ..routes.add((r) => r.path.contains('/report')
        ? (answer?.call() ?? json(<String, Object?>{}))
        : null);
  final client = await tester.runAsync(() => account(script));
  final mx = client!.matrixClient;
  await tester.pumpWidget(host(
      Builder(
          builder: (context) => TextButton(
              onPressed: () => switch (target) {
                    ReportTarget.message => ReportContentDialog.reportEvent(
                        context, mx, roomId, eventId),
                    ReportTarget.room =>
                      ReportContentDialog.reportRoom(context, mx, roomId),
                    ReportTarget.user => ReportContentDialog.reportUser(
                        context, mx, '@x:example.org'),
                  },
              // Not translated: a test button.
              child: const Text('open'))),
      scroll: false));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return script;
}

Future<void> send(WidgetTester tester) async {
  await tester.tap(find.byKey(ReportContentDialog.sendKey));
  await settle(tester);
}

void main() {
  setUpAll(prepareTests);

  testWidgets('sends the reason typed and says the report went through',
      (tester) async {
    final script = await openDialog(tester);
    expect(find.text(ReportContentDialog.promptReportMessage), findsOneWidget);

    await tester.enterText(
        find.byKey(ReportContentDialog.reasonFieldKey), 'scam link');
    await send(tester);

    final sent = script.where('POST', '/report/$eventId').single;
    expect(sent.body, {'reason': 'scam link'});
    expect(find.text(ReportContentDialog.messageReportSent), findsOneWidget);
  });

  testWidgets('the reason may be left empty', (tester) async {
    final script = await openDialog(tester);
    await send(tester);

    expect(script.where('POST', '/report/').single.body, isEmpty);
    expect(find.text(ReportContentDialog.messageReportSent), findsOneWidget);
  });

  testWidgets('a room and a user are reported from their own dialogs',
      (tester) async {
    var script = await openDialog(tester, target: ReportTarget.room);
    expect(find.text(ReportContentDialog.promptReportRoom), findsOneWidget);
    await send(tester);
    expect(script.where('POST', '/rooms/$roomId/report').single.body,
        {'reason': ''});

    await tester.pumpWidget(const SizedBox());
    script = await openDialog(tester, target: ReportTarget.user);
    expect(find.text(ReportContentDialog.promptReportUser), findsOneWidget);
    await send(tester);
    expect(script.where('POST', '/users/@x:example.org/report'), hasLength(1));
  });

  for (final locale in ['en', 'pt']) {
    for (final (errcode, status, failure, words) in [
      ('M_FORBIDDEN', 403, ReportFailure.forbidden, ('not let', 'não deixou')),
      (
        'M_NOT_FOUND',
        404,
        ReportFailure.notFound,
        ('could not find', 'não encontrou')
      ),
    ]) {
      testWidgets(
          '$errcode is shown as a sentence in $locale, and kept '
          'open to try again', (tester) async {
        await tester.runAsync(() => initializeMessages(locale));
        intl.Intl.defaultLocale = locale;
        addTearDown(() => intl.Intl.defaultLocale = null);
        var refuse = true;
        final script = await openDialog(tester,
            answer: () => refuse
                ? matrixError(errcode, status: status)
                : json(<String, Object?>{}));

        await send(tester);

        final sentence = ReportContentDialog.errorOf(failure);
        expect(sentence, contains(locale == 'pt' ? words.$2 : words.$1));
        expect(find.text(sentence), findsOneWidget);
        expect(find.text(ReportContentDialog.messageReportSent), findsNothing);

        refuse = false;
        await send(tester);
        expect(script.where('POST', '/report/'), hasLength(2));
        expect(find.text(sentence), findsNothing);
        expect(
            find.text(ReportContentDialog.messageReportSent), findsOneWidget);
      });
    }
  }
}
