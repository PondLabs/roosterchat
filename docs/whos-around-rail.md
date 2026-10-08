# Who's around

Request (2026-10-08): the space column had a tall empty stretch under the
spaces, from the "+" down to the profile. It now ends in a rail that says
who is in a voice channel right now, in every space of every account, and
offers a chair when nobody is.

## What the rail shows

Right under the "+" that adds a space (`SpaceSelector.trailing`), a bubble
per voice channel of every space of every account, the size of a space's
icon:

- **The channels with people in them first**, with the faces of up to four
  of them: one fills the tile, two sit corner to corner, three make a
  triangle, four a grid, and a fuller channel's fourth cell counts the rest
  ("+3"). A green ring around it breathes twice when the bubble appears and
  whenever someone comes or goes or a badge changes, then rests (never
  under a reduced-motion setting): a ring breathing all day would keep the
  app drawing frames all day. The DJ's record spins at the corner while
  their music plays, and a LIVE pill or a camera shows when someone shares
  their screen or camera, the badges the sidebar shows next to a name. Our
  own call comes first, then the fuller channels, then by name.
- **The quiet channels after them**, dimmed: the channel's picture at half
  strength or its initial, and a speaker in the corner, by space and then
  by name. Their tooltip says "It's quiet. Pull up a chair."
- Hover (desktop) names the channel, its space and everyone in it; a click
  opens the channel; right-click, or a long press on touch, opens the
  channel, opens its chat, or joins the call.
- **"+N"** past eight bubbles: seven and the count of the rest, which opens
  the whole list, "Who's around" (faces, channel, space, how many people)
  and then "Pull up a chair" (the quiet ones). The "+N" bubble wears the
  ring when a channel with people in it is among the hidden.
- Nothing at all while there is no voice channel anywhere.

Below the last bubble, down to the bottom of the column, the **night sky**
(`rooster/lib/ui/atoms/night_sky.dart`, `SpaceSelector.filler`): the
constellation of the login page, still and faint, so what is left of the
column reads as sky over the houses rather than as nothing. It is drawn
once in Dart (the login page's is a shader animating at 60 frames a
second), from a fixed seed, with more stars in a taller column and the ones
already there staying put, and gets no room once the list of spaces is
longer than the column.

Settings, App, Appearance, "Show who's around under the spaces" turns the
rail off (`preferences.showWhosAround`). While accounts are not mixed, it
lists the shown account's channels only.

## Where it comes from

`LiveVoiceChannels` (`rooster/lib/client/live_voice_channels.dart`) watches
every room with an `ActivitiesComponent`, of every account: the same call
memberships the sidebar reads under a channel
(`docs/voice-channel-members.md`), so whoever is listed there is in the
rail, with the same badges, and lapses at the same moment. Rooms that arrive
later are watched, rooms that go are dropped, a space that arrives after its
room is named once it does, and a sync that touches many rooms produces one
change (`onChanged`, coalesced in a microtask), and none when nothing the
rail shows changed.

"Join call" goes through `EntranceSoundGate.requestJoin`: the channel's
page opens and takes the request, the way it takes "Join Without Entrance
Sound", with the sound this time.

## What the tests guard

| Invariant | Guarded by |
|-----------|------------|
| Only channels with people in a real call are listed (not a widget's session, not an emptied call); our call first and us first in it; a channel appears when someone comes in and goes when the last one leaves, one change each, and a badge changing is a change; rooms that arrive later are watched and removed ones dropped; a space that arrives later is named; the chair's list goes by space then name, rooms outside a space last; nothing after dispose | `unit_test/live_voice_channels_test.dart` |
| Bubbles show the people's initials; a fuller channel's fourth cell counts the rest; the quiet channels follow the live ones, dimmed, by initial, and open on tap; a channel with people in it is not also listed as quiet; nine or more channels fold into +N, which lists who is around and then the quiet ones; a tap opens the channel; the rail follows the source (a quiet channel lights up and dims again) and the account filter; nothing without a voice channel anywhere | `unit_test/whos_around_rail_test.dart` |
| The trailing widget follows the footer, the filler takes the rest of a short column and gets no room in a long one | `unit_test/space_selector_layout_test.dart` |
| The sky is the same every time, a taller column adds stars without moving the ones there, none in no room | `unit_test/night_sky_test.dart` |
| A join request says whether it wants the entrance sound, is taken once, and expires | `unit_test/soundboard/entrance_sound_test.dart` |
