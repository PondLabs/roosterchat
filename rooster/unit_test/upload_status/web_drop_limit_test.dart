@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:rooster/ui/organisms/chat/dropped_files.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

/// A file of [bytes] dropped on the page, as the browser gives it: an
/// object URL of its `Blob`, with its size.
XFile _dropped(String name, int bytes) {
  final blob = web.Blob([Uint8List(bytes).toJS].toJS);
  return XFile(web.URL.createObjectURL(blob), name: name, length: bytes);
}

/// A drop in the browser goes through the server's limit by the file's
/// size before the page fetches any of it.
void main() {
  test(
      "a file over the server's limit dropped in the browser is refused by "
      'its size; one within it is attached', () async {
    final refused = <(int, int)>[];

    final attached = await attachmentsFromDroppedFiles(
        [_dropped('big.bin', 20), _dropped('small.bin', 5)],
        maxBytes: 10,
        onRefused: (bytes, limit) => refused.add((bytes, limit)),
        inBrowser: true);

    print('dropped in the browser: refused $refused, attached '
        '${[for (final a in attached) a.name]}');
    expect(refused, [(20, 10)]);
    expect([for (final a in attached) a.name], ['small.bin']);
  });
}
