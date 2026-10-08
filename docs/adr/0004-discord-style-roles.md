# Discord-style roles and permissions

**Status: proposed (2026-10-08).** Nothing here is built yet. This records what Matrix offers, what it lacks, and the plan we picked.

People coming from Discord expect its permission system: roles set once for the whole server, named and coloured, made of on/off switches, with per-channel overrides. Matrix has none of that. Its permissions are numbers, set room by room. We want Rooster to feel like Discord here, without waiting for the protocol and without leaving other Matrix clients behind.

## What Discord has

- **Roles** for the whole server: named, coloured, shown in the member list, and ordered. You can only manage roles below your own.
- **Switches**, about 40 of them: manage messages, kick, ban, manage channels, mention @everyone, attach files, embed links, use external emoji, connect, speak, video, stream, mute and move members.
- **Channel overrides**: each channel can allow or deny any switch, for a role or for one member. A private channel is just "@everyone cannot see it".
- Bots are often used for what the built-in system can't do: auto-roles, reaction roles, timed mutes.

## What Matrix has: power levels

Each room has one `m.room.power_levels` state event:

- every member has a number (default 0, admins 100);
- every action needs a minimum number: `kick`, `ban`, `redact` (others' messages), `invite`, and `notifications.room` (@room);
- every event type can need a minimum too (`events`), and `events_default` and `state_default` cover the rest. That gives read-only channels, and lets us limit who changes the name, pins, emoji packs, or our own `chat.commet.*` state (soundboard, DJ booth, channel categories);
- `org.matrix.msc3401.call.member` decides who may join a call.

Seeing a channel is decided by membership and join rules. The `restricted` join rule lets someone join only if they are already in one of a list of rooms. That is how a channel can be limited to the members of a space, or of any other room.

Rooster already has a power level editor per room (`matrix_room_permissions_page.dart`, with Owner, Admin, Moderator and Member presets). Nothing is shared across a space.

### What is missing compared with Discord

1. **Nothing is server-wide.** Power levels live in each room. A role has to be copied into every room of the space, and kept in sync as rooms, roles and members change.
2. **One number per member per room.** Permissions are a ladder, not a set of switches. "Can ban but not kick", or two roles with different, overlapping permissions, cannot be expressed exactly.
3. **Permissions follow event types, not content.** An image and a text message are both `m.room.message`, so "attach files", "embed links" and "use external emoji" have no equivalent.
4. **No named roles.** Other clients show numbers, or "Admin" and "Moderator" at 100 and 50.

## What the protocol is doing about it

| Proposal | What | Where it stands |
|---|---|---|
| [MSC2812](https://github.com/matrix-org/matrix-spec-proposals/pull/2812) | Role-based permissions (`m.role` events with explicit permissions) | Old draft; its author calls it an information dump. |
| [MSC4056](https://github.com/matrix-org/matrix-spec-proposals/pull/4056) | Role-based access control, mk II: `m.role` and `m.role_map`, ordered roles | Draft. Needs a new room version and an implementation. Last discussed April 2025. |
| [MSC3216](https://github.com/matrix-org/matrix-spec-proposals/pull/3216) | Space power levels flowing down to the rooms in it (`space_defaults`) | Open, stalled since 2021. Needs a new room version. |
| [Room version 12](https://matrix.org/blog/2025/09/17/matrix-v1.16-release/) ([MSC4289](https://www.matrix.org/docs/spec-guides/creator-power-level/)) | Room creators have unlimited power; upgrading a room needs 150 by default | In the spec since Matrix 1.16 (September 2025). |
| [MSC4284](https://matrix.org/blog/2025/04/introducing-policy-servers/) | Policy servers: a room names a server that every participating homeserver asks before accepting an event | Accepted. [policyserv](https://matrix.org/blog/2025/12/policyserv/) is open source and self-hostable. |

Even an accepted MSC4056 would only reach new rooms on a new room version, and only years from now. We do not wait for it.

## Options

- **Extend the protocol (our own MSC or room version).** Only matters for other clients, and takes years. No.
- **A Synapse module** (`check_event_allowed`, a [third-party rules callback](https://gogs.librecmc.org/RISCI_ATOM/synapse/src/master/docs/modules/third_party_rules_callbacks.md)). Can refuse any event on our own server. Synapse marks it experimental. Other homeservers do not run it, so with federation our server can end up disagreeing with the rest of the room about what it contains. Only safe for rooms nobody outside our server takes part in. No, except perhaps for a closed deployment.
- **A policy server.** Every homeserver in the room asks it, so it holds across federation, but only where those homeservers implement MSC4284. It can only refuse, never allow what power levels deny. Kept for later, for the switches power levels cannot express (point 3 above).
- **Roles as Rooster data, compiled into power levels and join rules.** Works on any homeserver, matrix.org included. Every client and server enforces the result, because it is plain Matrix. Limited to what power levels can express, which covers most of Discord's switches.
- **A bot that keeps the compiled result in sync.** The same, done automatically. This is what Discord-like Matrix communities already do ([Advanced Community Bot](https://git.ztfr.eu/Dome/Advanced-Community-Bot/src/commit/afcab3b173de3e641e66b8b554440447bbffbe1e) passes permissions from a space down to its rooms; [SpaceComet](https://zff.dev/faithcd/SpaceComet) moderates across a space).

## Decision

Roles are Rooster data in the space, and a **role engine** compiles them into each room's power levels and join rules. Rooster has the Discord-like UI. A bot keeps it in sync, and our LiveKit token service enforces the voice switches. A policy server may later cover what is left. No protocol change and no homeserver fork.

### Roles as state in the space

Under Commet's namespace, like the rest of our state (ADR 0002):

- `chat.commet.role`, one per role, `state_key` = role id: name, colour, icon, position, and the switches it grants.
- `chat.commet.member_roles`, one per member, `state_key` = user id: the role ids they hold. One event per member, so editing someone's roles never rewrites everyone's.
- `chat.commet.channel_overrides` in each room: allow or deny per switch, for a role or a member.

Who may edit them is itself a power level on those event types in the space, so it is enforced like everything else.

### Compiling to power levels

Roles are ordered, as on Discord. Each role gets its own power level from its position (higher position, higher number), and every member gets the highest level among their roles. In each room, after its overrides, every action and event type needs the lowest level among the roles that are granted it.

This is exact whenever permissions grow with position: every role above one that has a switch has it too. That is how most servers are set up (Member, Trusted, Moderator, Admin). When they don't, for example a lower role that may pin while a higher one may not, the compile cannot be exact: the higher role gets the switch too. The role editor shows this before saving ("Moderator will also be able to pin messages"). Fixing it exactly is left to the policy server.

### Channel visibility

- Each role that restricts visibility gets a hidden **role room**, whose members are the role's members.
- A channel visible only to some roles uses the `restricted` join rule, allowing members of those role rooms.
- Losing a role means leaving its role room, and being removed from the channels it opened.

### Voice

Rooster gets its LiveKit token from the service named in the homeserver's `.well-known` (`livekit_service_url`, `/sfu/get`). Our own token service can read the roles and grant per member what they may publish: microphone (Speak), camera (Video), screen share (Stream). Joining is already the call member power level. Muting or moving others goes through the LiveKit server API, from the same service. This is enforced by LiveKit itself, whatever the client.

### Other clients

They see ordinary power levels and join rules, so everything compiled is enforced for Element users too. They do not see role names or colours, only numbers. The levels stay meaningful (100 for admins, 50 for moderators) where the roles allow it.

## Plan

1. **Roles in Rooster.** The three state events, the compiler as plain Dart with unit tests, the role editor in space settings, coloured names, and the member list grouped by role. The admin's own client applies the compiled result when roles change. That is enough on matrix.org, with no server of ours.
2. **The role engine bot**, an application service next to our homeserver, reusing the same compiler. It applies changes automatically: on role edits, when someone joins, when a channel is added, and when someone loses a role. It needs power in every room it manages, so a space opts in by giving it that.
3. **Voice switches** in our LiveKit token service.
4. **Content switches, if needed**: attach files, embed links, external emoji, slow mode, as policy server rules.

## Open questions

- Hosting: phases 2 and 3 need services we run. That fits running our own homeserver, but phase 1 must not depend on it.
- Existing rooms: how a space adopts roles without losing the power levels it set by hand. Probably by importing them as roles first.
- Room version 12: creators sit above every role and cannot be demoted. The bot needs a level below creators and above every role it manages.
- How much of Discord's switch list to show at first. Probably only those power levels can enforce, so the editor never promises what nothing enforces.
