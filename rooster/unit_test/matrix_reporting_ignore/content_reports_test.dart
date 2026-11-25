// Criterion 1: reporting a message (`reportEvent`, never `score`, v1.18
// MSC4277), a room (`reportRoom`, v1.13) and a user (`reportUser`, v1.14)
// with an optional reason, and what the server's refusals become.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/reporting/matrix_content_reports.dart';

import 'fakes.dart';

const roomId = '!room:example.org';
const eventId = r'$event:example.org';
const userId = '@spammer:example.org';

/// Every report is taken, unless [refuse] answers first.
Future<(Script, MatrixContentReports)> reporter(
    {http.Response? Function(Seen)? refuse}) async {
  final script = Script();
  if (refuse != null) script.routes.add(refuse);
  script.routes.add((r) => r.method == 'POST' && r.path.contains('/report')
      ? json(<String, Object?>{})
      : null);
  final client = await account(script);
  return (script, MatrixContentReports(client.matrixClient));
}

Seen onlyReport(Script script) {
  final sent = script.where('POST', '/report').toList();
  expect(sent, hasLength(1));
  return sent.single;
}

void main() {
  setUpAll(prepareTests);

  group('reportEvent', () {
    test('posts the reason to the event report path, without score', () async {
      final (script, reports) = await reporter();
      await reports.reportEvent(roomId, eventId, reason: 'spam links');

      final sent = onlyReport(script);
      expect(sent.path, '/_matrix/client/v3/rooms/$roomId/report/$eventId');
      expect(sent.body, {'reason': 'spam links'});
      expect((sent.body as Map).containsKey('score'), isFalse);
    });

    test('leaves the reason out when there is none or it is blank', () async {
      for (final reason in [null, '', '   ']) {
        final (script, reports) = await reporter();
        await reports.reportEvent(roomId, eventId, reason: reason);

        final body = onlyReport(script).body as Map;
        expect(body, isEmpty, reason: 'reason: "$reason"');
      }
    });

    test('trims the reason it sends', () async {
      final (script, reports) = await reporter();
      await reports.reportEvent(roomId, eventId, reason: '  rude \n');
      expect(onlyReport(script).body, {'reason': 'rude'});
    });
  });

  group('reportRoom', () {
    test('posts the reason to the room report path', () async {
      final (script, reports) = await reporter();
      await reports.reportRoom(roomId, reason: 'illegal content');

      final sent = onlyReport(script);
      expect(sent.path, '/_matrix/client/v3/rooms/$roomId/report');
      expect(sent.body, {'reason': 'illegal content'});
    });

    test('sends a blank reason when none was given (the key is required)',
        () async {
      final (script, reports) = await reporter();
      await reports.reportRoom(roomId);
      expect(onlyReport(script).body, {'reason': ''});
    });
  });

  group('reportUser', () {
    test('posts the reason to the user report path', () async {
      final (script, reports) = await reporter();
      await reports.reportUser(userId, reason: 'harassment');

      final sent = onlyReport(script);
      expect(sent.path, '/_matrix/client/v3/users/$userId/report');
      expect(sent.body, {'reason': 'harassment'});
    });

    test('sends a blank reason when none was given (the key is required)',
        () async {
      final (script, reports) = await reporter();
      await reports.reportUser(userId, reason: ' ');
      expect(onlyReport(script).body, {'reason': ''});
    });
  });

  group('refusals', () {
    for (final (errcode, status, failure) in [
      ('M_FORBIDDEN', 403, ReportFailure.forbidden),
      ('M_NOT_FOUND', 404, ReportFailure.notFound),
      ('M_UNRECOGNIZED', 404, ReportFailure.unsupported),
      ('M_LIMIT_EXCEEDED', 429, ReportFailure.rateLimited),
      ('M_UNKNOWN', 500, ReportFailure.other),
    ]) {
      test('$errcode from each report is $failure', () async {
        final (_, reports) = await reporter(
            refuse: (r) => r.path.contains('/report')
                ? matrixError(errcode, status: status)
                : null);
        for (final send in [
          () => reports.reportEvent(roomId, eventId),
          () => reports.reportRoom(roomId),
          () => reports.reportUser(userId),
        ]) {
          final error =
              await send().then<Object?>((_) => null, onError: (Object e) => e);
          expect(error, isA<matrix.MatrixException>());
          expect(ReportFailure.of(error!), failure);
        }
      });
    }

    test('an error that is not the server\'s is other', () {
      expect(ReportFailure.of(Exception('offline')), ReportFailure.other);
    });
  });
}
