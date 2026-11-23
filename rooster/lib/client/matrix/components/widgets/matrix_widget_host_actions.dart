import 'package:rooster/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:matrix/matrix.dart' as matrix;

/// What a widget's capabilities do to the client on the widget's behalf.
///
/// Kept apart from the capabilities so a test can stand in for it and see
/// that nothing runs while a capability is not granted.
class MatrixWidgetHostActions {
  const MatrixWidgetHostActions();

  /// MSC2931: opens a matrix.to link (a room, a user) inside Rooster.
  Future<void> navigate(MatrixWidgetRunner runner, Uri uri) {
    return LinkUtils.open(uri,
        clientId: runner.client.identifier,
        contextRoomId: runner.room?.identifier,
        context: navigator.currentContext);
  }

  /// MSC3973: the homeserver's user directory search.
  Future<matrix.SearchUserDirectoryResponse> searchUserDirectory(
      MatrixWidgetRunner runner, String term,
      {int? limit}) {
    return runner.client.matrixClient.searchUserDirectory(term, limit: limit);
  }

  /// MSC4407 through MSC4354: sends a room event that stays sticky for
  /// [durationMs]. Returns the event id.
  ///
  /// In an encrypted room the content is encrypted first, and the send fails
  /// rather than going out in the clear when it cannot be.
  Future<String> sendStickyEvent(MatrixWidgetRunner runner,
      {required String type,
      required Map<String, dynamic> content,
      required int durationMs}) async {
    final room = runner.room!.matrixRoom;
    final client = room.client;

    var sendType = type;
    var body = content;
    if (room.encrypted) {
      final encryption = client.encryption;
      if (encryption == null || !client.encryptionEnabled) {
        throw StateError('Cannot encrypt a sticky event for this room');
      }
      body = await encryption.encryptGroupMessagePayload(room.id, content,
          type: type);
      sendType = matrix.EventTypes.Encrypted;
    }

    final txnId = client.generateUniqueTransactionId();
    final response = await client.request(
        matrix.RequestType.PUT,
        '/client/v3/rooms/${Uri.encodeComponent(room.id)}'
        '/send/${Uri.encodeComponent(sendType)}/${Uri.encodeComponent(txnId)}',
        query: {'org.matrix.msc4354.sticky_duration_ms': '$durationMs'},
        data: body);

    return response['event_id'] as String;
  }
}
