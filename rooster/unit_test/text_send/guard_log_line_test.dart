@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/debug/log.dart';
import 'package:rooster/diagnostic/speed_log/text_send_trace.dart';

/// A text send step that fails to be timed leaves one line in the app's
/// log, with the error's fixed name and nothing of the error itself: its
/// message could hold the text being sent, a room or event id, or a URL,
/// and its type reads `minified:xx` in a web release build.
void main() {
  const text = 'my secret message';
  const room = '!room1234:example.org';
  const event = r'$event5678';
  const url = 'https://matrix.example.org/_matrix/client/v3/rooms';

  final cases = <String, Object>{
    'other': StateError('$text in $room, event $event at $url'),
    'timeout': TimeoutException('$text $room', const Duration(seconds: 3)),
    'socket': const SocketException('$text $room $url'),
    'client': http.ClientException('$text $room', Uri.parse(url)),
  };

  for (final MapEntry(key: name, value: error) in cases.entries) {
    test('a step that throws ${error.runtimeType}: "($name)" and nothing else',
        () {
      final before = Log.log.length;
      var ran = false;

      TextSendTrace.guard(() {
        ran = true;
        throw error;
      });

      final entries = Log.log.skip(before).toList();
      final lines = [for (final e in entries) e.rawContent];
      print('log: $lines');
      expect(ran, isTrue);
      expect(entries.single.type, LogType.warning);
      // The line as `Log.w` writes it: the app's prefix and the warning's
      // colour around the fixed text.
      expect(lines, [
        '[Rooster (${Log.prefix})] '
            '\x1B[33mSpeed log: a text send step was not timed ($name)\x1B[0m'
      ]);
      for (final secret in [text, room, event, url, 'example.org']) {
        expect(lines.single, isNot(contains(secret)));
      }
      expect(lines.single, isNot(contains(error.runtimeType.toString())));
    });
  }
}
