import 'package:matrix/matrix.dart' as matrix;

/// What came of asking to forget a room.
enum ForgetOutcome {
  /// We asked the homeserver to forget the room.
  forgotten,

  /// The homeserver forgets rooms as soon as they are left
  /// (`m.forget_forced_upon_leave`, Matrix v1.18, MSC4267), so nothing was
  /// sent: the room is already forgotten.
  forcedByServer,
}

/// Rooms we have left (or were removed from), and forgetting them.
class MatrixArchivedRooms {
  MatrixArchivedRooms(this.client);

  final matrix.Client client;

  bool? _forgetForced;

  /// Whether the homeserver forgets rooms on leave by itself. Asked once,
  /// from `/v3/capabilities`; a server that does not say is taken not to.
  Future<bool> forgetForcedUponLeave() async {
    final known = _forgetForced;
    if (known != null) return known;
    final capabilities = await client.getCapabilities();
    return _forgetForced =
        capabilities.mForgetForcedUponLeave?.enabled ?? false;
  }

  Future<List<matrix.Room>> load() => client.loadArchive();

  /// Forgets [room], unless the server already did when we left it.
  Future<ForgetOutcome> forget(matrix.Room room) async {
    if (await forgetForcedUponLeave()) {
      client.archivedRooms.removeWhere((r) => r.room.id == room.id);
      return ForgetOutcome.forcedByServer;
    }
    await room.forget();
    return ForgetOutcome.forgotten;
  }
}
