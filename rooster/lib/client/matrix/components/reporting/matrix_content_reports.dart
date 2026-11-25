import 'package:matrix/matrix.dart' as matrix;

/// Why the homeserver turned a report down, for the report dialog to say
/// so in the app's language.
enum ReportFailure {
  /// `M_FORBIDDEN`: for example a message in a room we are not in.
  forbidden,

  /// `M_NOT_FOUND`: the message, room or user is not known to the server.
  notFound,

  /// `M_UNRECOGNIZED`: a homeserver older than the endpoint (room reports
  /// are Matrix v1.13, user reports v1.14).
  unsupported,

  /// `M_LIMIT_EXCEEDED`.
  rateLimited,

  /// Anything else, a lost connection included.
  other;

  static ReportFailure of(Object error) {
    if (error is! matrix.MatrixException) return other;
    return switch (error.errcode) {
      'M_FORBIDDEN' => forbidden,
      'M_NOT_FOUND' => notFound,
      'M_UNRECOGNIZED' => unsupported,
      'M_LIMIT_EXCEEDED' => rateLimited,
      _ => other,
    };
  }
}

/// Reports a message, a room or a user to the homeserver's administrators
/// (Client-Server API "Reporting content").
class MatrixContentReports {
  MatrixContentReports(this.client);

  final matrix.Client client;

  /// The reason as typed, or null when only blank.
  static String? _reason(String? reason) {
    final trimmed = reason?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// `POST /rooms/{roomId}/report/{eventId}`. The reason is left out when
  /// there is none, and `score` is never sent (removed in v1.18, MSC4277).
  Future<void> reportEvent(String roomId, String eventId, {String? reason}) =>
      client.reportEvent(roomId, eventId, reason: _reason(reason));

  /// `POST /rooms/{roomId}/report` (v1.13). The body's `reason` is
  /// required and may be blank.
  Future<void> reportRoom(String roomId, {String? reason}) =>
      client.reportRoom(roomId, _reason(reason) ?? '');

  /// `POST /users/{userId}/report` (v1.14). The body's `reason` is
  /// required and may be blank.
  Future<void> reportUser(String userId, {String? reason}) async {
    await client.reportUser(userId, _reason(reason) ?? '');
  }
}
