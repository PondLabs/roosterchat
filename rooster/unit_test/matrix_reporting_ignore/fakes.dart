import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';

import '../matrix_room_directory/fakes.dart';
import '../speed_log/fake_account.dart';

export '../matrix_room_directory/fakes.dart'
    show Script, Seen, json, matrixError, prepareTests, host, settle;

const ignoredListPath = '/account_data/m.ignored_user_list';

/// Answers the ignore list's PUTs; the rest goes to the SDK's fake.
http.Response? acceptIgnoreList(Seen r) =>
    r.method == 'PUT' && r.path.endsWith(ignoredListPath)
        ? json(<String, Object?>{})
        : null;

Iterable<Seen> ignoreListWrites(Script script) =>
    script.where('PUT', ignoredListPath);

/// The `ignored_users` a write put on the server, as a map.
Map<String, Object?> writtenUsers(Seen write) =>
    ((write.body as Map)['ignored_users'] as Map).cast<String, Object?>();

var _accounts = 0;

/// A logged-in Rooster account (`@test:fakeServer.notExisting`) whose
/// requests go through [script] first, then to the SDK's fake homeserver.
Future<MatrixClient> account(Script script) async {
  script.routes.add(acceptIgnoreList);
  final client = await fakeAccount(
      'reporting_ignore_${_accounts++}_${DateTime.now().microsecondsSinceEpoch}',
      ScriptedAccountTransport(script));
  script.seen.clear();
  return client;
}

/// [update] arrives in a sync, as another session's change would.
Future<void> sync(matrix.Client mx, matrix.SyncUpdate update) async {
  await mx.database.transaction(() => mx.handleSync(update));
  await Future<void>.delayed(Duration.zero);
}

/// The ignore list as another session of the account wrote it.
Future<void> syncIgnoreList(matrix.Client mx, List<String> users,
        {Map<String, Object?> extra = const {}}) =>
    sync(
        mx,
        matrix.SyncUpdate(nextBatch: 'ignore_${users.join()}', accountData: [
          matrix.BasicEvent(type: 'm.ignored_user_list', content: {
            ...extra,
            'ignored_users': {for (final u in users) u: <String, Object?>{}},
          }),
        ]));
