import 'package:matrix/matrix.dart' as matrix;

/// Why a server administration call did not go through.
enum ServerAdminFailure { forbidden, unsupported, notFound, other }

/// What the server says about one account.
class ServerAdminLookup {
  ServerAdminLookup({this.whois, this.locked, this.suspended, this.failure});

  final matrix.WhoIsInfo? whois;
  bool? locked;
  bool? suspended;

  /// The first refusal among the three calls, if any.
  final ServerAdminFailure? failure;
}

/// Server administration of other accounts: `GET /v3/admin/whois` and
/// `GET`/`PUT /v1/admin/lock|suspend` (Matrix v1.18, MSC4323). Only server
/// administrators may use them; the others get `403 M_FORBIDDEN`.
class MatrixServerAdmin {
  MatrixServerAdmin(this.client);

  final matrix.Client client;

  static ServerAdminFailure failureOf(Object error) {
    if (error is! matrix.MatrixException) return ServerAdminFailure.other;
    return switch (error.error) {
      matrix.MatrixError.M_FORBIDDEN => ServerAdminFailure.forbidden,
      matrix.MatrixError.M_UNRECOGNIZED => ServerAdminFailure.unsupported,
      matrix.MatrixError.M_NOT_FOUND => ServerAdminFailure.notFound,
      _ => ServerAdminFailure.other,
    };
  }

  /// Asks all three; each answers or is left out, and the first refusal is
  /// kept in [ServerAdminLookup.failure]. Never throws a server's refusal.
  Future<ServerAdminLookup> lookUp(String userId) async {
    final failures = <ServerAdminFailure>[];
    Future<T?> attempt<T>(Future<T> Function() call) async {
      try {
        return await call();
      } catch (e) {
        failures.add(failureOf(e));
        return null;
      }
    }

    final whois = await attempt(() => client.getWhoIs(userId));
    final locked = await attempt(() => client.getUserLocked(userId));
    final suspended = await attempt(() => client.getUserSuspended(userId));
    return ServerAdminLookup(
      whois: whois,
      locked: locked,
      suspended: suspended,
      failure: failures.contains(ServerAdminFailure.forbidden)
          ? ServerAdminFailure.forbidden
          : failures.firstOrNull,
    );
  }

  /// Locks or unlocks [userId]; returns what the server answers.
  Future<bool> setLocked(String userId, bool locked) =>
      client.setUserLocked(userId, locked);

  /// Suspends or unsuspends [userId]; returns what the server answers.
  Future<bool> setSuspended(String userId, bool suspended) =>
      client.setUserSuspended(userId, suspended);
}
