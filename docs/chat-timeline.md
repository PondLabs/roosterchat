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

A message that arrives while the reader is at the latest messages, with the
window in front, floats up into place: it rises 40 px and fades in over
450 ms with a slight overshoot (`_FloatIn`, as in the demo video). Only
those: not the messages a room opens with, nor a page of history, nor a
message that arrives unseen. It is keyed by its event, so the message that
takes another's place in the list gets a state of its own. Nothing moves
with the system's reduced motion on.

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

## Threads: read receipts and unread badges

A thread is read apart from the room (threaded receipts, Matrix v1.4,
MSC3771):

- **The room's timeline** moves our fully read marker to its newest event
  (`/read_markers`, no receipt in it) and sends our receipt with
  `thread_id: "main"` on its newest event outside any thread
  (`MatrixThreadedReceipts.threadOf`: a reply in a thread, or a reaction or
  edit of one, is not). A server before v1.4 gets the unthreaded receipt as
  before. Nothing changes for `following` or the "New messages" line: they
  are worked out from the timeline as before, and the receipt is sent at the
  same moments.
- **A thread**, open beside the chat (`MatrixThreadTimeline.markAsRead`),
  sends our receipt on its newest reply the server has, with `thread_id`
  set to its root. A thread with no reply yet, or a server before v1.4, gets
  none. One request per reply.
- Both are `m.read`, or `m.read.private` when the room (or else the
  account) keeps receipts private.
- **"Mark as Read"** in the room's menu still sends an unthreaded receipt,
  which reads the threads too.

The homeserver reports a thread's unread notifications apart from the
room's (`unread_thread_notifications`, MSC3773) because the sync filter
asks for them (`MatrixClient.syncFilter`; the SDK defines the filter again
for sessions from before, see `third_party/README.md`). The SDK keeps them
in `Room.unreadThreadNotifications`; `MatrixThreadUnread` reads them and
says when they change.

- `ThreadUnreadBadge` shows the count on a thread's root in the timeline
  (after its latest reply) and on the thread in the threads panel. It is
  red when one of them calls on us (`highlight_count > 0`) and goes once
  they are zero: a sync that brings the room's counts names every thread
  with any, and reading the thread here clears it at once.
- The room's own badge (`MatrixRoom.notificationCount` and
  `highlightedNotificationCount`) adds the threads to the room's counts, so
  a reply in a thread still lights the room in the sidebar. Reading the
  room's timeline leaves the threads' share until they are read.

### The threads panel

**Threads** in the room's menu lists the room's threads, newest activity
first (`GET /_matrix/client/v1/rooms/{roomId}/threads`, v1.4): all of them,
or **My threads** (`include=participated`). Each shows who started it, its
first message, how many replies it has, the latest one and its unread
badge. The next page (`from`) loads when the end of the list comes into
view. Picking a thread opens it beside the chat.

## Jump to date

**Jump to date** in the room's menu, or a click on a day's separator in the
timeline, asks for a day and shows the room's first message of it
(`MatrixJumpToDate`, `GET /_matrix/client/v1/rooms/{roomId}/timestamp_to_event`,
Matrix v1.6, MSC3030). It asks for the first event at or after the day's
local midnight (`dir=f`, the time in milliseconds) and, when the room has
nothing from then on, the last one before it (`dir=b`). The timeline then
goes there as it does for a pinned message (`EventBus.jumpToEvent`), loading
the messages around it when they are not loaded. When the room has no
message either way (`M_NOT_FOUND`), or the server is older than v1.6 (or
answers `M_UNRECOGNIZED`), a toast says so in the app's language. A
thread's day separators do not jump: a thread shows its replies only.

Tests: `unit_test/matrix_threads/`.
