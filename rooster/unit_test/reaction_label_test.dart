// What a reaction reads as where the timeline shows it as text (the folded
// summary in developer mode, a failed send): never the SDK's "Unknown
// message format of type m.reaction".
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_add_reaction.dart';

void main() {
  String label({String? key, String? shortcode}) =>
      MatrixTimelineEventAddReaction.describe(
          sender: 'Alice', key: key, shortcode: shortcode);

  test('a unicode reaction shows the emoji', () {
    expect(label(key: '👍'), 'Alice reacted 👍');
  });

  test('a custom emoji shows its shortcode when the reaction carries one', () {
    expect(label(key: 'mxc://example.org/abc', shortcode: 'partyparrot'),
        'Alice reacted :partyparrot:');
    expect(label(key: 'mxc://example.org/abc', shortcode: ':partyparrot:'),
        'Alice reacted :partyparrot:');
  });

  test('a custom emoji without a name is said to be one', () {
    expect(label(key: 'mxc://example.org/abc'),
        'Alice reacted with a custom emoji');
  });

  test('a reaction without a key still names who reacted', () {
    expect(label(), 'Alice reacted');
  });
}
