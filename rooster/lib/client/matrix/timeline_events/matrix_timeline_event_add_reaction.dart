import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event_add_reaction.dart';
import 'package:intl/intl.dart';

class MatrixTimelineEventAddReaction extends MatrixTimelineEvent
    implements TimelineEventAddReaction {
  MatrixTimelineEventAddReaction(super.event, {required super.client});

  /// A reaction has no body: without this the timeline's folded summary
  /// (developer mode) and a failed send showed the SDK's "Unknown message
  /// format of type m.reaction".
  @override
  String get plainTextBody {
    final relation = event.content['m.relates_to'];
    final key = relation is Map ? relation['key'] : null;
    final shortcode = event.content['shortcode'] ??
        event.content['com.beeper.reaction.shortcode'];
    return describe(
      sender: event.senderFromMemoryOrFallback.calcDisplayname(),
      key: key is String ? key : null,
      shortcode: shortcode is String ? shortcode : null,
    );
  }

  /// "Alice reacted 👍", or for a custom emoji its :shortcode: when the
  /// reaction carries one.
  static String describe(
      {required String sender, String? key, String? shortcode}) {
    if (key == null || key.isEmpty) return messageUserReacted(sender);
    if (!key.startsWith('mxc://')) return messageUserReactedWith(sender, key);
    if (shortcode != null && shortcode.isNotEmpty) {
      return messageUserReactedWith(
          sender, shortcode.startsWith(':') ? shortcode : ':$shortcode:');
    }
    return messageUserReactedWithCustomEmoji(sender);
  }

  static String messageUserReactedWith(String user, String emoji) =>
      Intl.message("$user reacted $emoji",
          name: "messageUserReactedWith",
          args: [user, emoji],
          desc: "A reaction: the user who reacted, then the emoji, or its "
              ":shortcode: for a custom one");

  static String messageUserReactedWithCustomEmoji(String user) =>
      Intl.message("$user reacted with a custom emoji",
          name: "messageUserReactedWithCustomEmoji",
          args: [user],
          desc: "A reaction with a custom emoji whose name is unknown, with "
              "the user who reacted");

  static String messageUserReacted(String user) => Intl.message("$user reacted",
      name: "messageUserReacted",
      args: [user],
      desc: "A reaction whose emoji is unknown, with the user who reacted");
}
