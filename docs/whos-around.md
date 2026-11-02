# Who's around

Request (2026-10-08): on the Home screen, the list beside the space column
(favorites and direct messages) was blank for anyone with neither, a tall
empty panel. It now starts with who is in a voice channel right now, in
every space of every account, and the quiet channels to pull up a chair in;
and the Direct Messages header, with its button, stays even with no
conversation yet.

## What the Home screen's list shows

At the top (`WhosAroundSection`,
`rooster/lib/ui/organisms/home_screen/whos_around_section.dart`, in
`ImportantRoomsList` on desktop and in the mobile layout's left panel):

- **Who's around**: a row per voice channel with people in it, with the
  faces of up to four of them in one tile (`FaceCluster`: one fills it, two
  sit corner to corner, three make a triangle, four a grid, and a fuller
  channel's fourth cell counts the rest), the channel's name, its space and
  how many people, the DJ's spinning record while their music plays, and a
  LIVE pill or a camera when someone shares their screen or camera (the
  badges the sidebar shows next to a name). At the end of the row, **Join
  call**, which opens the channel and has its page join, the way "Join
  Without Entrance Sound" does, with the sound
  (`EntranceSoundGate.requestJoin`); the channel whose call we are in says
  "You're in here" instead. Our own call comes first, then the fuller
  channels, then by name. A tap on the row opens the channel; the menu
  (right-click, long press on touch) opens the channel, opens its chat, or
  joins the call.
- **Pull up a chair**: the voice channels with nobody in them, dimmed, by
  space and then by name, five at a time with "N more channels" for the
  rest. A tap opens the channel.
- Nothing at all while there is no voice channel anywhere, or with
  Settings, App, Appearance, "Show who's around on Home" off
  (`preferences.showWhosAround`). While accounts are not mixed, only the
  shown account's channels.

Then favorites as before, and direct messages, whose header and "+" used
to show only once there was a conversation: they stay, with "No
conversations yet." under them until there is one.

## Where it comes from

`LiveVoiceChannels` (`rooster/lib/client/live_voice_channels.dart`, owned by
`MainPageState`) watches every room with an `ActivitiesComponent`, of every
account: the same call memberships the sidebar reads under a channel
(`docs/voice-channel-members.md`), so the list and the sidebar agree, with
the same badges, and lapse at the same moment. Rooms that arrive later are
watched, rooms that go are dropped, a space that arrives after its room is
named once it does, and a sync that touches many rooms produces one change
(`onChanged`, coalesced in a microtask), and none when nothing shown
changed.

## What the tests guard

| Invariant | Guarded by |
|-----------|------------|
| Only channels with people in a real call are listed (not a widget's session, not an emptied call); our call first and us first in it; a channel appears when someone comes in and goes when the last one leaves, one change each, and a badge changing is a change; rooms that arrive later are watched and removed ones dropped; a space that arrives later is named; the quiet list goes by space then name, rooms outside a space last; nothing after dispose | `unit_test/live_voice_channels_test.dart` |
| Rows show the people's initials, how many and the space, and a join button that joins; our own call says "You're in here" instead; a fuller channel's fourth cell counts the rest; the quiet channels follow under "Pull up a chair", five at a time, and open on tap; nothing without a voice channel or with the setting off; the list follows the source and the account filter | `unit_test/whos_around_section_test.dart` |
| A join request says whether it wants the entrance sound, is taken once, and expires | `unit_test/soundboard/entrance_sound_test.dart` |
