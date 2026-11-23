import 'package:html/parser.dart' as html_parser;
import 'package:matrix/matrix.dart' as matrix;

/// A room topic as `m.room.topic` content carries it: the Matrix v1.15 rich
/// topic (`m.topic`, a list of representations in `m.text`) when there is
/// one, with the legacy `topic` string as the fallback.
///
/// The representations are read by the SDK's own parser
/// ([matrix.Room.richTopicRepresentation]), as the room's current topic is.
/// [html] is the sender's HTML as it came: whoever shows it passes it
/// through `MatrixHtmlParser`, which sanitizes it like a message's.
class MatrixRichTopic {
  const MatrixRichTopic({required this.plain, this.html});

  /// The topic as text: the `text/plain` representation, else the legacy
  /// `topic`, else the text of the HTML one. Empty when there is no topic.
  final String plain;

  /// The `text/html` representation, when it has something in it.
  final String? html;

  bool get isEmpty => plain.trim().isEmpty && html == null;

  static const empty = MatrixRichTopic(plain: '');

  /// Reads [content] of an `m.room.topic` event; anything malformed is
  /// skipped, so redacted (`{}`) or broken content is an empty topic.
  factory MatrixRichTopic.fromContent(Map<String, Object?>? content) {
    if (content == null) return empty;

    String? usable(String? value) =>
        value != null && value.trim().isNotEmpty ? value : null;

    final html =
        usable(matrix.Room.richTopicRepresentation(content, 'text/html'));
    final legacy = content['topic'];
    final plain =
        usable(matrix.Room.richTopicRepresentation(content, 'text/plain')) ??
            usable(legacy is String ? legacy : null) ??
            (html == null ? null : _textOf(html)) ??
            '';
    return MatrixRichTopic(plain: plain, html: html);
  }

  /// The room's current topic.
  factory MatrixRichTopic.ofRoom(matrix.Room room) =>
      MatrixRichTopic.fromContent(
          room.getState(matrix.EventTypes.RoomTopic)?.content);

  static String? _textOf(String html) {
    final text = html_parser.parse(html).body?.text.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
