@TestOn('vm')
library;

import 'dart:io';

import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:test/test.dart';

/// The section of `docs/speed-log.md` under the heading [title].
String _section(String doc, String title) {
  final start = doc.indexOf('\n$title\n');
  expect(start, isNot(-1), reason: 'no section $title');
  final end = doc.indexOf('\n## ', start + 1);
  return doc.substring(start, end == -1 ? doc.length : end);
}

/// The names in the first column of the table that follows [heading].
Set<String> _tableNames(String doc, String heading) {
  final start = doc.indexOf(heading);
  expect(start, isNot(-1), reason: 'no table after $heading');
  final names = <String>{};
  var seenTable = false;
  for (final line in doc.substring(start).split('\n').skip(1)) {
    if (!line.startsWith('|')) {
      if (seenTable) break;
      continue;
    }
    seenTable = true;
    final match = RegExp(r'^\| `([a-z0-9_]+)`').firstMatch(line);
    if (match != null) names.add(match.group(1)!);
  }
  return names;
}

void main() {
  // A Windows checkout has CRLF line ends.
  final doc =
      File('../docs/speed-log.md').readAsStringSync().replaceAll('\r\n', '\n');

  test('every listed name is in the doc, as code', () {
    for (final name in [
      ...SpeedOperation.all,
      ...SpeedStep.all,
      ...SpeedValue.all,
      ...SpeedOutcome.all,
      ...SpeedError.all,
      invalidSpeedName,
    ]) {
      expect(doc, contains('`$name`'), reason: name);
    }
  });

  test('the step tables list the steps each span writes', () {
    expect(_tableNames(doc, '`text_send`, a text message'), {
      SpeedStep.send,
      SpeedStep.echo,
      SpeedStep.echoPainted,
      SpeedStep.queueWait,
      SpeedStep.request,
      SpeedStep.retry,
      SpeedStep.answer,
      SpeedStep.keyRequest,
      SpeedStep.outboundSession,
    });
    expect(_tableNames(doc, '`sync`, one round'), {
      SpeedStep.serverWait,
      SpeedStep.processing,
      SpeedStep.cleanUp,
      SpeedStep.clientWork,
      SpeedStep.nextRequest,
      SpeedStep.error,
    });
    expect(_tableNames(doc, '`image_prepare`, an attached picture'), {
      SpeedStep.queueWait,
      SpeedStep.header,
      SpeedStep.decode,
      SpeedStep.encode,
      SpeedStep.reduce,
    });
    expect(_tableNames(doc, '`file_send`, a file sent'), {
      SpeedStep.attached,
      SpeedStep.previewPainted,
      SpeedStep.prepared,
      SpeedStep.echo,
      SpeedStep.upload,
      SpeedStep.request,
      SpeedStep.retry,
      SpeedStep.confirmed,
      SpeedStep.asyncUpload,
      SpeedStep.uploadFirst,
      SpeedStep.reserve,
      SpeedStep.uploaded,
    });
    expect(_tableNames(doc, '`voice_join`, a voice join'), {
      SpeedStep.leavePrevious,
      SpeedStep.outputDevice,
      SpeedStep.foci,
      SpeedStep.openIdToken,
      SpeedStep.sfuToken,
      SpeedStep.sfuLivekitCloud,
      SpeedStep.sfuSelfHosted,
      SpeedStep.microphoneEarly,
      SpeedStep.prepareConnection,
      SpeedStep.membershipClearWait,
      SpeedStep.membershipWrite,
      SpeedStep.connect,
      SpeedStep.connectWebsocket,
      SpeedStep.connectJoinResponse,
      SpeedStep.connectMedia,
      SpeedStep.microphoneOptions,
      SpeedStep.microphoneOpen,
      SpeedStep.sfuRegion,
      SpeedStep.sfuRegionOther,
      SpeedStep.microphonePublished,
      SpeedStep.firstRemoteAudio,
    });
  });

  test('the doc gives the fixed list as the rule for names', () {
    final never = _section(doc, '## What is never recorded');
    expect(never, contains('speed_names.dart'));
    expect(never, isNot(contains('[a-z][a-z0-9_]*')));
  });
}
