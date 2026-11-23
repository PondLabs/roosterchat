// Criterion 2: `m.ignored_user_list` gains and loses users in the account
// data, keeps what else it held, follows other sessions' changes from the
// sync, and refuses our own ID.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/components/reporting/matrix_ignored_users.dart';

import 'fakes.dart';

const bob = '@bob:example.org';
const carol = '@carol:example.org';

void main() {
  setUpAll(prepareTests);

  test('ignoring writes the user into the account data and applies at once',
      () async {
    final script = Script();
    final mx = (await account(script)).matrixClient;
    final ignored = MatrixIgnoredUsers.of(mx);
    final changes = <Set<String>>[];
    ignored.onChanged.listen(changes.add);

    await ignored.ignore(bob);

    final writes = ignoreListWrites(script).toList();
    expect(writes, hasLength(1));
    expect(writes.single.path,
        '/_matrix/client/v3/user/${mx.userID}/account_data/m.ignored_user_list');
    expect(writtenUsers(writes.single), {bob: <String, Object?>{}});
    // Before any sync brings the list back.
    expect(ignored.isIgnored(bob), isTrue);
    expect(ignored.users, [bob]);
    expect(mx.ignoredUsers, [bob]);
    expect(changes, [
      {bob}
    ]);
  });

  test('ignoring keeps the users and fields already on the list', () async {
    final script = Script();
    final mx = (await account(script)).matrixClient;
    await syncIgnoreList(mx, [carol], extra: {'org.example.note': 'kept'});
    final ignored = MatrixIgnoredUsers.of(mx);

    await ignored.ignore(bob);

    final write = ignoreListWrites(script).single;
    expect(writtenUsers(write).keys, unorderedEquals([bob, carol]));
    expect((write.body as Map)['org.example.note'], 'kept');
    expect(ignored.users, [bob, carol]);
  });

  test('unignoring removes only that user, and shows them again', () async {
    final script = Script();
    final mx = (await account(script)).matrixClient;
    await syncIgnoreList(mx, [bob, carol]);
    final ignored = MatrixIgnoredUsers.of(mx);
    final changes = <Set<String>>[];
    ignored.onChanged.listen(changes.add);

    await ignored.unignore(bob);

    expect(writtenUsers(ignoreListWrites(script).single), {carol: {}});
    expect(ignored.isIgnored(bob), isFalse);
    expect(ignored.isIgnored(carol), isTrue);
    expect(changes, [
      {bob}
    ]);
  });

  test('neither leaves rooms nor clears the cache, unlike the SDK', () async {
    final script = Script();
    final client = await account(script);
    final mx = client.matrixClient;
    final roomsBefore = mx.rooms.length;
    var cleared = false;
    mx.onCacheCleared.stream.listen((_) => cleared = true);

    await MatrixIgnoredUsers.of(mx).ignore(bob);
    await MatrixIgnoredUsers.of(mx).unignore(bob);

    expect(script.where('POST', '/leave'), isEmpty);
    expect(mx.rooms.length, roomsBefore);
    expect(cleared, isFalse);
  });

  test('ignoring our own ID is refused, and nothing is written', () async {
    final script = Script();
    final mx = (await account(script)).matrixClient;
    final ignored = MatrixIgnoredUsers.of(mx);

    expect(ignored.canIgnore(mx.userID!), isFalse);
    await expectLater(
        ignored.ignore(mx.userID!), throwsA(isA<CannotIgnoreSelf>()));

    expect(ignoreListWrites(script), isEmpty);
    expect(ignored.isIgnored(mx.userID), isFalse);
  });

  test('an ID that is not a Matrix ID is refused, and nothing is written',
      () async {
    final script = Script();
    final mx = (await account(script)).matrixClient;
    final ignored = MatrixIgnoredUsers.of(mx);

    expect(ignored.canIgnore('bob'), isFalse);
    await expectLater(ignored.ignore('bob'), throwsA(isA<ArgumentError>()));
    expect(ignoreListWrites(script), isEmpty);
  });

  test('a failed write leaves the list as it was', () async {
    final script = Script()
      ..routes.add((r) => r.method == 'PUT' && r.path.endsWith(ignoredListPath)
          ? matrixError('M_FORBIDDEN')
          : null);
    final mx = (await account(script)).matrixClient;
    final ignored = MatrixIgnoredUsers.of(mx);

    await expectLater(ignored.ignore(bob), throwsA(anything));
    expect(ignored.isIgnored(bob), isFalse);
  });

  test('a list changed by another session arrives in the sync', () async {
    final mx = (await account(Script())).matrixClient;
    final ignored = MatrixIgnoredUsers.of(mx);
    final changes = <Set<String>>[];
    ignored.onChanged.listen(changes.add);

    await syncIgnoreList(mx, [bob]);
    expect(ignored.isIgnored(bob), isTrue);

    await syncIgnoreList(mx, [carol]);
    expect(ignored.isIgnored(bob), isFalse);
    expect(ignored.isIgnored(carol), isTrue);
    expect(changes, [
      {bob},
      {bob, carol},
    ]);
  });
}
