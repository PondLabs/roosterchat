# Profile

Settings > Account > Profile is where you edit what other people see of you.
Every field is on the page, says who sees it, and changes a draft that the
preview beside it (the real profile card, and one message of yours in a chat)
shows at once. Nothing is sent until **Save changes**; parts that fail stay in
the draft. The code is in
`rooster/lib/ui/pages/settings/categories/account/profile/`. Your own profile
card has an **Edit profile** button that opens this page for that account
(`AppSettingsPage(editProfileOf:)`).

## Who sees what

| Field | Stored in | Seen by |
| --- | --- | --- |
| Picture, display name | `avatar_url`, `displayname` | every Matrix app |
| Banner | profile field `chat.commet.profile_banner` | Rooster, Commet |
| Pronouns | profile field `io.fsky.nyx.pronouns` (MSC4247) | Rooster and some other apps |
| Status message | profile field `chat.commet.profile_status`, and presence where the homeserver shares it | Rooster; other apps through presence |
| About me | `chat.commet.profile_bio` and `gay.fomx.biography` (MSC4440) | Rooster and some other apps |
| Local time | `m.tz` | any app that shows it |
| Name color | profile field `eu.she-a.color` (MSC4522) | Rooster, Sable |
| Card colors | profile field `chat.commet.profile_color_scheme` | Rooster, Commet |
| Badges | profile field `chat.commet.profile_badges` | Rooster, Commet; only badges already earned on Commet can be picked |

Two things are about other people and only you see them, so they live on
other people's cards, not here: a nickname (account data
`chat.commet.petnames`) and a recolored name (account data
`im.vector.setting.override_colors`, Element's key). A nickname set on
yourself before this page existed is ignored.

## Name colors

A name is drawn in: your own recolor of that person, else the color they
picked, else the hash of their user ID that Element and Cinny also use
(`MatrixMember.hashColor`).

The picked color is MSC4522's unstable `eu.she-a.color`,
`{"on_dark": "#rrggbb", "on_light": "#rrggbb"}`, one profile field for every
room and space. Rooster offers a palette (`name_color_palette.dart`) whose
pairs read on both themes; a value from another app is drawn as it is.
Per-room colors in `m.room.member` (also in MSC4522) are not written: Synapse
drops unknown keys from member events on every name or picture change, and
writing every room costs one rate-limited state event per room.

Other people's colors are fetched, never pushed: `NameColorCache` asks
`GET /profile/{user}/eu.she-a.color` for the names actually drawn (timeline
senders, reply quotes, member list rows, your own name at the bottom left),
at most four at a time. An answer is kept for 30 minutes. "Not set",
forbidden or unsupported counts as no color; any other failure keeps what was
known and asks again after a minute. `UserColorComponent.onColorChanged` tells
those widgets to repaint, also when the theme switches between light and dark.
Places that draw names without listening (thread footers, polls, mention
pills, notifications) pick a color up the next time they are built.
