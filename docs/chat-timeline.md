# The chat timeline: following new messages, the "New messages" line, mentions

Request (2026-10-08): a text channel open on screen should always show its
latest message. It sat still while messages piled up below it, and people
missed them. Also, make clear which messages are new with the existing
"New messages" line, and highlight a message that mentions us, as Discord
does.

## How the timeline is laid out

`RoomTimelineWidgetView` is a reversed `CustomScrollView` with two slivers
around a center line: the **history** sliver (the center) grows up from it,
the **recent** sliver grows down from it. Scroll offset 0 with an empty recent
sliver is the bottom of the list. Events at index 0 are the newest.

## Following the latest messages

`following` says the reader is at the latest messages. Only the reader's
own scrolling changes it (`onScroll` while `ownScrolls` is 0): true within
50 px of the bottom, false once they scroll further up. The app's own
scrolling to the bottom does not change it.

**Why this changed.** It used to be read from the scroll position whenever
a message came in, and new messages went into the recent sliver, below the
center. Two things then took the view off the bottom without the reader
doing anything:

- A message growing after it had been scrolled to: a link preview such as an
  X card, or an image, loading.
- The next message arriving while the last one was still scrolling into
  view.

From then on the view no longer counted as at the bottom, and nothing new
scrolled into view.

**While following**, everything is in the history sliver (`settleAtBottom`)
at offset 0. A new message is inserted at its start, so the newest message
stays at the bottom however it grows.

- In front of the reader, the new message scrolls into view (`scrollToBottom`).
- With the window behind others, it is simply put there (`stickToBottom`),
  with no animation.
- `stickToBottom` holds the view at the very bottom for a few frames. A list
  laying out children it had not built yet corrects the scroll position to
  keep what was on screen in place. That correction used to leave **Jump to
  latest** one message short of the bottom.

**Reading further up** (not following), new messages go into the recent
sliver, so what is being read stays put. The button at the bottom counts
them ("2 new messages") and jumps down to them. Scrolling down to the bottom
and stopping there (`onScrollEnd`) settles the view and follows again.

Sending a message while reading further up jumps back to the latest, as on
Discord.

Only live messages count. A page of the past loaded while scrolling down a
timeline opened at an old message (`canLoadFuture`) is not "new".

## The "New messages" line

The line goes above `lastReadEventId`:

- **When the room opens**, the first message after our read marker. It went
  above the newest message before: the loop looking for the first one kept
  going.
- **While the room is open**, the first message from someone else that
  arrives unseen, with the window not in front (`AppLifecycleState` other
  than `resumed`) or while reading further up. It stays there through the
  messages after it. Once the reader is back at the latest messages with the
  window in front (`acknowledgeIfLooking`), the next message they miss moves
  it.
- **Sending a message** removes it: we are caught up.

The room still opens at the latest message, with the line above the first
unread one.

## Mentions

A message that calls on us gets a gold bar and tint
(`TimelineEventLayoutMessage.mentionColor`, the brand's yolk), whatever the
theme. `TimelineEvent.mentionsSelf` decides, and our own messages never
count. It is true when any of these hold:

- `m.mentions` lists us.
- `m.mentions` has `room`, from someone allowed to ping the room.
- The message has no `m.mentions` (an older client) and our push rules
  highlight it, which is how such clients mention us by name. With
  `m.mentions` present the list is the whole answer: the Matrix spec has the
  rules matching our name in the text not apply, so a message that only
  says our name is not highlighted, as on Discord. A room muted by a push
  rule does not highlight this way.

A reply to one of our messages is highlighted too, while that message is in
the timeline (`isReplyToSelf`). Replies Rooster sends now list whoever they
answer in `m.mentions`, as the Matrix spec has it (Element does the same),
so the person replied to is notified and sees the reply highlighted
wherever it loads.

Tests: `unit_test/timeline_follow_latest_test.dart`,
`unit_test/mention_highlight_test.dart`.
