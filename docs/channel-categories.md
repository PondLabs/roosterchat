# Channel categories and channel actions

Request (2026-10-07): text channels and voice channels apart in a space's
sidebar, as on Discord, under headings the space's admins can make
themselves, and Discord's buttons on a channel (open its chat, invite,
settings, invite to voice, a voice channel's status).

## What the sidebar shows

`SpaceList` (`rooster/lib/ui/atoms/space_list.dart`) lists a space's
channels under headings, `ChannelCategories.layout` decides which:

- The admin's own headings first, in the order they set, each with the
  channels they put under it. Shown even when empty, to put channels under.
- **Text channels** and **Voice channels**, built-in headings that take
  every channel of their kind no heading of the admin's holds. Shown only
  with channels in them. Their names are translated unless an admin renamed
  them.
- Inside any heading, text channels before voice channels, each in the
  space's own order (the `order` of `m.space.child`, set by dragging rooms
  on the space's page).
- A voice channel is a room created as `org.matrix.msc3417.call`
  (`Room.roomType`), joinable here or not. Photo albums and calendars count
  as text.
- Spaces inside the space come after the headings, as before, and list
  their channels under their own headings, without the built-in ones.

A heading folds when tapped; which ones are folded is kept on this device
(`preferences.collapsedChannelCategories`). A folded heading still shows the
open channel, one with something unread, and the voice channel we are in.

## Where the headings are kept

One state event in the space, read by `MatrixSpaceCategoriesComponent`:

```json
{
  "type": "chat.commet.space_categories",
  "state_key": "",
  "content": {
    "categories": [
      {"id": "k2j4c9xq0m1z", "name": "Info", "rooms": ["!rules:x", "!news:x"]},
      {"id": "text"},
      {"id": "voice", "name": "Hangouts"}
    ]
  }
}
```

- `text` and `voice` are the built-in headings; any other id is the admin's.
  A list missing a built-in heading gets it back at its end, so no channel
  is ever left out. A room under two headings shows under the first.
- Changing it takes the power level for that state event, by default the
  space's admins and moderators; everyone else sees no editing entries.
- Other Matrix clients ignore the event and list the space as they always
  did. Headings are not subspaces: nobody has to join anything for them.
- It is among the client's `importantStateEvents`, so the headings are
  there from the first frame.

## Editing (admins)

Right-click (long press on touch) a heading: collapse/expand, create a
channel under it, create a category, rename it (a built-in one goes back to
its translated name when renamed to nothing), move it up or down, delete it
(its channels go back under the built-in headings). The `+` on a heading
creates a channel under it, or adds an existing room: a text channel under
**Text channels**, a voice channel under **Voice channels**, any kind under
one of the admin's. A channel's own menu has **Move to category**.

## Channel buttons

Under the pointer, or while open, a channel's row shows (desktop; on touch
the same entries are in its long-press menu):

- **Open chat** (voice channels and other special rooms): the room's text
  chat instead of the call.
- **Invite people**: the invite dialog. Who is picked is invited to the
  channel and to the space, which they may not be in yet.
- **Edit channel**: the room's settings.

## Voice channel status

A line under a voice channel's name saying what it is up to, kept in the
channel as `chat.commet.voice_channel_status` (state key `""`, content
`{"status": "Movie night"}`, `{}` when cleared, at most 100 characters).
Everyone sees it. While in the call, whoever may send that state event sees
**Set a channel status** (or the status, with a pencil) and can change it.
Voice channels Rooster creates give that event power level 0, so anyone in
them may set it, as on Discord; older ones keep their state default, usually
moderators, until an admin lowers it.

## Invite to voice

While we are in a voice channel's call, an **Invite to voice** row sits
under the people in it (closed with its `×` for the rest of that call). It
opens the channel's and the space's people who are not in the call, five
at first and **See more…** for all of them, searchable. Inviting someone
sends them a direct message, in a DM opened with them if there is none,
with a `matrix.to` link to the channel (`Room.getShareLink`); in Rooster the
link opens the channel. Each person is invited once per channel while the
app runs. The same list is in the channel's menu while in the call.
