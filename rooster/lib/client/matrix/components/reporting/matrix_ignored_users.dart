import 'dart:async';

import 'package:matrix/matrix.dart' as matrix;

/// Thrown when the user tries to put their own Matrix ID on their ignore
/// list.
class CannotIgnoreSelf implements Exception {
  const CannotIgnoreSelf();

  @override
  String toString() => 'CannotIgnoreSelf';
}

/// The user's `m.ignored_user_list` account data: who they ignore, and
/// hiding what those people send.
///
/// The SDK's own `ignoreUser` leaves their direct chats, declines their
/// invites and clears the whole local cache to drop their messages; an
/// invite declined that way cannot come back when the user is unignored,
/// and the app does not rebuild its rooms after a cache clear. Here the
/// list is written as it is and the client hides their messages and
/// invites itself, so both come back when the user is unignored, with no
/// restart. The homeserver also stops sending what they send from then on.
class MatrixIgnoredUsers {
  static const type = 'm.ignored_user_list';
  static const _key = 'ignored_users';

  static final Expando<MatrixIgnoredUsers> _byClient = Expando();

  /// The one for [client], following its account data from then on.
  static MatrixIgnoredUsers of(matrix.Client client) =>
      _byClient[client] ??= MatrixIgnoredUsers._(client);

  MatrixIgnoredUsers._(this.client) {
    _known = _read();
    // The list arrives in a sync's account data, from this session or
    // another one of the same account.
    client.onSync.stream
        .where((sync) =>
            sync.accountData?.any((event) => event.type == type) == true)
        .listen((_) => _refresh());
  }

  final matrix.Client client;

  final StreamController<Set<String>> _changed =
      StreamController.broadcast(sync: true);

  /// The users who were just ignored or unignored, after the list changed
  /// here or in a sync (another session of the same account).
  Stream<Set<String>> get onChanged => _changed.stream;

  late Set<String> _known;
  matrix.BasicEvent? _readFrom;

  Set<String> _read() {
    final event = client.accountData[type];
    _readFrom = event;
    final users = event?.content[_key];
    if (users is! Map) return const {};
    return users.keys.whereType<String>().toSet();
  }

  Set<String> get _current {
    // Read again only when the account data event was replaced (the store
    // loaded at startup, a sync not yet announced). This may run while a
    // widget builds, so the listeners hear of it after.
    if (!identical(client.accountData[type], _readFrom)) {
      _refresh(later: true);
    }
    return _known;
  }

  void _refresh({bool later = false}) {
    final before = _known;
    final now = _read();
    _known = now;
    final changed = before.difference(now).union(now.difference(before));
    if (changed.isEmpty) return;
    if (later) {
      scheduleMicrotask(() => _changed.add(changed));
    } else {
      _changed.add(changed);
    }
  }

  /// Who the user ignores, sorted.
  List<String> get users => _current.toList()..sort();

  bool isIgnored(String? userId) => userId != null && _current.contains(userId);

  /// Whether [event] is hidden from the timeline: a message or other
  /// non-state event from someone the user ignores, as homeservers filter
  /// them. State events (their joins and leaves) stay.
  bool hides(matrix.Event event) =>
      event.stateKey == null &&
      event.senderId != client.userID &&
      isIgnored(event.senderId);

  bool canIgnore(String userId) =>
      userId != client.userID && userId.isValidMatrixId;

  /// Adds [userId] to the list. Refuses our own ID with
  /// [CannotIgnoreSelf], and an ID that is not a Matrix ID.
  Future<void> ignore(String userId) async {
    if (userId == client.userID) throw const CannotIgnoreSelf();
    if (!userId.isValidMatrixId) {
      throw ArgumentError.value(userId, 'userId', 'not a Matrix ID');
    }
    if (isIgnored(userId)) return;
    await _write((users) => users[userId] = <String, Object?>{});
  }

  /// Takes [userId] off the list: their messages and invites show again.
  Future<void> unignore(String userId) async {
    if (!isIgnored(userId)) return;
    await _write((users) => users.remove(userId));
  }

  Future<void> _write(void Function(Map<String, Object?> users) change) async {
    // Keeps whatever else the event holds, and each entry's own object.
    final content = Map<String, Object?>.of(
        client.accountData[type]?.content ?? const <String, Object?>{});
    final previous = content[_key];
    final users = previous is Map
        ? Map<String, Object?>.of(previous.cast<String, Object?>())
        : <String, Object?>{};
    change(users);
    content[_key] = users;

    await client.setAccountData(client.userID!, type, content);

    // In effect now, not when the sync brings it back.
    client.accountData[type] = matrix.BasicEvent(type: type, content: content);
    _refresh();
  }
}
