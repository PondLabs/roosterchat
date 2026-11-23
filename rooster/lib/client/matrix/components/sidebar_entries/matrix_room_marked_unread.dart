import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/debug/log.dart';

/// A room marked unread by hand (v1.12, MSC2867): room account data
/// `{"unread": true}` that lights the room's dot in the sidebar however many
/// notifications it has.
class MatrixMarkedUnread {
  static const stableType = 'm.marked_unread';

  /// What clients wrote before the type became stable; still read, never
  /// written.
  static const legacyType = 'com.famedly.marked_unread';

  /// Whether [room] is marked unread: the stable type when it is there,
  /// otherwise the legacy one.
  static bool isMarked(matrix.Room room) {
    if (room.membership != matrix.Membership.join) return false;
    final content = room.roomAccountData[stableType]?.content ??
        room.roomAccountData[legacyType]?.content;
    return content?['unread'] == true;
  }

  /// [isMarked] for any room of the app; false for rooms of other
  /// protocols.
  static bool of(Room room) => room is MatrixRoom && isMarked(room.matrixRoom);

  /// Marks [room] unread or not, always in `m.marked_unread`. The SDK
  /// changes its copy first, so the sidebar follows before the server
  /// answers.
  static Future<void> setMarked(matrix.Room room, bool unread) async {
    if (isMarked(room) == unread) return;
    // A legacy mark is cleared by a stable `false`, which then wins.
    await room.markUnread(unread);
  }

  /// Takes the mark off [room] once it has been read; failures are logged,
  /// the mark then stays until the next read.
  static void clearOnRead(matrix.Room room) {
    if (!isMarked(room)) return;
    setMarked(room, false).catchError((Object e, StackTrace s) {
      Log.onError(e, s, content: "Could not clear the room's unread mark");
    });
  }
}
