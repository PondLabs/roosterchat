/// Orders the writes to one device's call membership state event.
///
/// Hanging up clears the membership, and that request can still be in flight,
/// or be retried by the SDK, when the user rejoins. The late clear would then
/// erase the new membership and leave them in the call but invisible to
/// everyone, with the LIVE badge gone (issue #48).
class CallMembershipWrites {
  CallMembershipWrites._();

  static final Map<String, Future<void>> _pending = {};

  /// Registers a clear of [stateKey] that later writes have to wait for.
  /// Returns [write] unchanged, so the caller still sees its result.
  static Future<T> clearing<T>(String stateKey, Future<T> write) {
    // Never fails: waiting for this only orders the writes, the caller deals
    // with the error.
    final done = write.then<void>((_) {}, onError: (_) {});
    _pending[stateKey] = done;
    done.whenComplete(() {
      if (identical(_pending[stateKey], done)) _pending.remove(stateKey);
    });
    return write;
  }

  /// The key a join's outcome is registered under (see `CallJoin`): our
  /// membership's [stateKey] is the same in every room, so a join in one
  /// room must not wait for a join in another.
  static String joinKey(String roomId, String stateKey) => "$roomId $stateKey";

  /// The latest join of each [joinKey] that wrote our membership.
  static final Map<String, Object> _claims = {};

  /// A join of [joinKey] is writing our membership. From here an earlier
  /// join of that key still running is [superseded].
  static Object claim(String joinKey) {
    final claim = Object();
    _claims[joinKey] = claim;
    return claim;
  }

  /// Whether a later join of [joinKey] has written our membership since
  /// [claim] and has not given it back: then the join of [claim], undone,
  /// must not clear it. A rejoin only waits so long for the join before it
  /// (see [settled]); that join's clear landing late would erase the new
  /// membership and leave us in the call, listed nowhere (issue #48).
  static bool superseded(String joinKey, Object claim) {
    final latest = _claims[joinKey];
    return latest != null && !identical(latest, claim);
  }

  /// A join undone gives its [claim] back once its clear is done, and a
  /// join that got in once its session has ended: an earlier join still
  /// running may then clear what it wrote.
  static void release(String joinKey, Object claim) {
    if (identical(_claims[joinKey], claim)) _claims.remove(joinKey);
  }

  /// Waits for a clear of [stateKey] that is still in flight. Bounded: a
  /// request that never lands must not stop the user from joining.
  static Future<void> settled(String stateKey,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final pending = _pending[stateKey];
    if (pending == null) return;
    try {
      await pending.timeout(timeout);
    } catch (_) {
      // Logged where the clear was issued.
    }
  }
}
