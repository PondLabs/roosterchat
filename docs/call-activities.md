# Call activities

A call activity is a game played inside a voice channel: someone starts
it from the call's controls (the rocket), everyone in the call sees it
and joins with one tap, and the session lives only as long as the call
does (like the DJ booth's queue). The framework is generic - the games
register themselves in it - so future activities bolt on without new
infrastructure.

## The pieces

- `client/components/call_activity/` - the contracts: the [CallActivity]
  descriptor (id, display name, player range, and the hooks the stage
  runs a game through - see "Adding a game" below), the typed registry, the
  wire protocol (JSON envelopes on the LiveKit data channel, topic
  `chat.commet.activity.v1`, with part-assembly past the packet limit)
  and the [CallActivitySession]: host-authoritative, with host election
  when the host vanishes, handoff when it leaves on purpose, and roster
  of players and spectators.
- `client/matrix/components/call_activity/` - the Matrix side: the
  session's room state (`chat.commet.call_activity`, one event per
  session, state key the session id behind an underscore - the id is the
  host's LiveKit identity, and Synapse refuses a state key that starts
  with "@" unless it is the sender's own user id - this is what people
  outside the call see), the LiveKit transport, and the component that
  ties a live call to its session and clears the state when the host's
  session ends.
- The games: `client/components/sunny_side_putt/` (the model layer) and
  `ui/organisms/sunny_side_putt/` (the game); see sunny-side-putt.md.
- `ui/organisms/call_activity/` - the shared UI: the picker (the shelf
  of activities), the stage (the game takes the call's view while the
  participant videos shrink into a strip), and the join pill. None of it,
  nor the call view, names a game: what they show of one comes from its
  descriptor.

## Adding a game

A game registers one `CallActivity` in `CallActivityRegistry` at startup
(`initGuiRequirements` in `main.dart`; Sunny Side Putt's is
`registerSunnySidePutt()` in `ui/organisms/sunny_side_putt/putt_session.dart`).
Besides its `id` (the namespaced event type, e.g. `chat.commet.putt`),
`displayName` and player range, the descriptor carries:

- `launchOptions(context)` - asks the launcher how to play (a mode, a
  course) before anything is written; null from it means they backed out.
  Leave it out to launch straight away.
- `createController(call)` - this client's `CallActivityController` of a
  session, built when we launch, join, or come back to a session we hold
  a seat in. `call` (a `CallActivityCallContext`) has the session, each
  call identity's name and avatar, `cameraOf(identity)` - that
  participant's camera `VoipStream`, asked again on each build - and
  `onEnded`, to call when the session ends under us. The controller is a
  `Listenable` the stage rebuilds on; `hostStart(options)` takes the host
  seat with what `launchOptions` returned, `buildStage(context, onLeave:)`
  is the view under the stage's header (null shows "Loading"), `leave()`
  tells the session we are out, and `dispose()` releases what the game
  holds, its sound included.
- `drawsPlayerVideos` - the game draws the players' cameras itself (from
  `cameraOf`): the stage's strip then shows only the people in the call
  who do not play.
- `availability()` - whether this device runs the game:
  `CallActivityAvailability.unavailable(reason)` keeps it from being
  launched or joined here, and the shelf and the invite show the reason
  (the game's own `Intl.message`, or "Not available on this device")
  in place of their buttons. A game that needs face tracking says so
  where there is none.

The room list's badges only need the `id`, the name and the `icon`; a
descriptor without `createController` cannot be launched or joined.

## A game with secrets

Everything in a session's state reaches every client, the host's too, so
a secret cannot ride it. Two things in the session are for that:

- `sendTo(identities, message)` - the addressed lane: an opaque message
  from any participant to the ones it picks (LiveKit's destination
  identities), heard on `direct` with its authenticated sender. Nobody
  else receives it, and a message for nobody is not sent.
- `hostPart(key, json)` - a component's own part of the state, in the
  snapshot's `parts` beside the game's payload: the game's next payload
  does not drop it, and an elected host finds it in the last state it
  heard.

Cock-a-Doodle-Who?'s plaques are built on both
(`client/components/cock_a_doodle_who/secret/`): everyone holds every
plaque but their own, and the host publishes only a ledger that says
nothing an owner may not know. See adr/0007-plaque-secret.md.

## Getting in and out

While someone plays and we do not, their game has a tile of the call's
grid, the way a shared screen has, with the join pill in its middle
("ggflores23 started Sunny Side Putt", Join). Nothing is streamed into
it: joining is how the game is seen.

The rocket is in two places: the call's own controls, and the voice panel
at the bottom of the sidebar, so it is there whatever room is open. In the
sidebar it opens the call and its shelf; while we are in an activity it is
lit and one press leaves it (through the call's view when that is showing,
so the game's view and sound go with it, else the session is told
directly). On the stage the header's exit button leaves at once, over a
running game too: the game's own leave sits behind its menu and a
question. Esc leaves as well where the game does not take the key.

## How a session lives

1. Someone opens the picker and launches an activity (choosing the
   mode). Their client takes the host seat: it writes the room state
   and announces the session on the wire.
2. Everyone in the call gets the join pill and the shelf's "started"
   row; joining puts the client in the roster (players up to the
   activity's maximum, spectators beyond).
3. The host's client runs the game's own engine and publishes its
   states (full snapshots plus the accepted-move journal); the others
   run the same engine fed by those and stay in step.
4. The host leaving hands the seat over (the followers re-elect the
   lowest present identity, and the new host carries the snapshot
   sequence on, so the roster it corrects is not dropped as stale by
   everyone who heard a higher number); the host that left is out of its
   own roster at once, so its badge goes with it and the join pill can
   take it back in. The last one out ends the session and its room state
   goes with it.
5. A session dies with the call it was played in. Leaving the call (or
   the connection dropping it) drops every session we followed: each is
   told we are out, so the host drops us from its roster now rather than
   when LiveKit gets round to reporting us gone, and then it is disposed
   - its transport with it. A session left running after its call was
   gone kept the game alive, listed everyone still in it (a dead
   transport still answers for the roster it last heard) and made every
   later launch in that channel a silent no-op. A session that ends
   while the call lives (its last player out, or its host's goodbye) is
   disposed the same way, its transport with it. Joining the call again
   starts from the room state, never from the session of the call that
   ended.

## In the room list and the call's sounds

A running activity is not listed as a second call under the voice
channel: everyone in it gets the activity's icon next to their name
("Playing Sunny Side Putt", "Watching Sunny Side Putt" for a
spectator). Outside the call only the host is known, from the room
state, and only while they are in the call; inside it the session's
roster adds the players and spectators, and a session nobody holds any
more (its host left without clearing the state) gives no badge. A
third-party widget's members are still listed under its own name. In
our own call, someone (us too) launching or joining an activity plays
`activity_joined.ogg`, someone leaving it (or it ending)
`activity_left.ogg`, once the roster has kept still for 300 ms (both, the
join first, when both happened), and not while deafened, like the screen
share cues. They are made by
`docs/brand/src/build_call_sounds.py`.

## Who may launch

Launching writes `chat.commet.call_activity`, and the others in the call
find the session only through it, so a launch whose write the homeserver
refuses is undone and the call view says why. Voice channels we create
open the event to everyone (power level 0); older channels keep the
room's state default, usually moderators only, and their other members
get "Only moderators can start activities in this channel." State left
by a host who went without clearing it (it lives up to 6 hours) is
ignored once nobody in the call holds that session: it shows no Join and
does not stop a new launch.

## Testing

- `flutter test unit_test/call_activity` - protocol, session lifecycle
  (launch, join, capacity, election, handoff, inputs, addressed messages
  and state parts) on the in-memory transport, whose `delivered` record
  says what each client was sent, and what the LiveKit transport
  publishes; `call_activity_ui` - the picker and stage widgets, and a fake
  second game run through the call view's hooks (launch, stage, cameras,
  the strip, an unavailable game).
- The voice e2e (`integration_test/activities/`) runs two real clients
  through a whole hole when the integration stack (Synapse + LiveKit +
  the auth service, `scripts/integration-server-livekit.sh`) is up, and
  skips cleanly when it is not.
