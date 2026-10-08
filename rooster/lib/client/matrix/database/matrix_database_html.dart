import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:universal_html/html.dart' as html;

Future<DatabaseApi> getMatrixDatabaseImplementation(String clientName,
    {bool onDatabaseIsolate = true, bool readOnly = false}) async {
  // Asked for, not waited for: nothing here uses the answer, and Firefox
  // can leave the promise open behind a permission prompt.
  unawaited(html.window.navigator.storage?.persist().catchError((_) => false));
  // init already opens the IndexedDB connection.
  return MatrixSdkDatabase.init(clientName);
}

Future<DatabaseApi?> getLegacyMatrixDatabaseImplementation(
    String clientName) async {
  return null;
}
