import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:rooster/debug/log.dart';

/// Threaded read receipts (Matrix v1.4, MSC3771): a receipt names the
/// thread it reads, a thread root's event id or `main` for the room's own
/// timeline, so reading one does not mark the others read.
class MatrixThreadedReceipts {
  /// The `thread_id` of the room's own timeline.
  static const mainThreadId = 'main';

  /// Whether the homeserver takes `thread_id` in receipts (Matrix v1.4).
  /// The versions are cached by the SDK, so this costs no request.
  static Future<bool> supported(matrix.Client client) async {
    try {
      final versions = await client.getVersions();
      return versions.versions.any((v) => isMatrixVersionAtLeast(v, 1, 4));
    } catch (e, s) {
      Log.onError(e, s, content: "Could not read the server's versions");
      return false;
    }
  }

  /// Sends our receipt for [eventId] in [threadId]: public (`m.read`) or
  /// private (`m.read.private`) as the room, or else the account, prefers.
  static Future<void> send(
    matrix.Room room,
    String eventId, {
    required String threadId,
    bool? public,
  }) {
    final isPublic = public ?? room.client.receiptsPublicByDefault;
    return room.client.postReceipt(
      room.id,
      isPublic ? matrix.ReceiptType.mRead : matrix.ReceiptType.mReadPrivate,
      eventId,
      threadId: threadId,
    );
  }

  /// The thread [event] belongs to, as far as [lookup] can tell: the root
  /// it replies in, the thread of the event it annotates, edits or
  /// references, otherwise [mainThreadId]. Null when that event is not
  /// known and could be in a thread.
  static String? threadOf(
      matrix.Event event, matrix.Event? Function(String eventId) lookup,
      {int depth = 0}) {
    final relation = event.content['m.relates_to'];
    if (relation is! Map) return mainThreadId;
    final relType = relation['rel_type'];
    final target = relation['event_id'];
    if (relType == matrix.RelationshipTypes.thread) {
      return target is String ? target : null;
    }
    // A reply that is not in a thread (`m.in_reply_to` alone) stays in the
    // main timeline.
    if (relType == null || target is! String) return mainThreadId;
    if (depth > 3) return null;
    final related = lookup(target);
    if (related == null) return null;
    return threadOf(related, lookup, depth: depth + 1);
  }
}
