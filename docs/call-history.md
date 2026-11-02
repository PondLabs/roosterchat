# Call history

A voice channel's header has a **Call history** button (the clock icon),
and a space's page has one for all its voice channels. It shows a day at a
time, with arrows to go back: how many calls there were, the time with
anyone in voice, the most people at once, each person's time in voice (and
how long they shared their screen, their camera, or played music as the
DJ), and every call with its channel, times and who was in it.

## Where it comes from

Nothing new is written or stored. Each member's client writes their call
membership on joining, again every half minute while in the call (with
what they share and whether they are the DJ), and empty on leaving
(see `voice-channel-members.md`). Every one of those writes stays in the
room's history, so the room itself is the record:

- `CallHistoryLoader` (`client/matrix/components/voip_room/`) pages back
  through `/messages` asking for `org.matrix.msc3401.call.member` events
  alone, a thousand at a time, as far as the day shown needs (plus five
  hours, for a call that began before it). It keeps what it fetched for the
  rest of the run; opened again, it fetches only what was written since.
- `callsFrom` (`call_history.dart`) turns those writes into calls. Per
  device: a stay starts at the join (`created_ts`) and ends at the empty
  write, or at a new join from the same device. With neither, a lapsed short
  window (half-minute writes) ends where it lapsed, within two minutes of
  when the app died; a lapsed window of hours (before 2026-10-07, or other
  clients) ends at its last write, since nothing says when after that. Still
  open: ongoing. A person's devices count once. A call is a run of time with
  anyone in the channel; a gap under a minute does not split it.
- `VoiceActivitySummary` adds a day up, counting only the part of a call
  inside it (a call across midnight counts on both days).

## Limits

- Only what members' clients wrote: calls before Rooster wrote these keys,
  or from other clients, have joins and leaves but no shares or DJ.
- Before 2026-10-07 an app that died without leaving counts to its last
  write, which could be up to an hour early.
- Fetching goes back through every membership write: a busy day is a few
  thousand events, a few requests.
- Only rooms the user is in, as anything in Matrix.

## Tests

`unit_test/call_history_test.dart` (calls from writes: leaves, crashes with
short and long windows, rejoins, two devices, shares, gaps, days across
midnight) and `unit_test/call_history_view_test.dart` (paging back only as
far as asked, picking up new writes on reopening, the page).
