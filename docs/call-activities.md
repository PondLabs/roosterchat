# Call activities

A call activity is a game played inside a voice channel: someone starts
it from the call's controls (the rocket), everyone in the call sees it
and joins with one tap, and the session lives only as long as the call
does (like the DJ booth's queue). The framework is generic - the games
register themselves in it - so future activities bolt on without new
infrastructure.

## The pieces

- `client/components/call_activity/` - the contracts: the [CallActivity]
  descriptor (id, display name, player range), the typed registry, the
  wire protocol (JSON envelopes on the LiveKit data channel, topic
  `chat.commet.activity.v1`, with part-assembly past the packet limit)
  and the [CallActivitySession]: host-authoritative, with host election
  when the host vanishes, handoff when it leaves on purpose, and roster
  of players and spectators.
- `client/matrix/components/call_activity/` - the Matrix side: the
  session's room state (`chat.commet.call_activity`, one event per
  session, state key the session id - this is what people outside the
  call see), the LiveKit transport, and the component that ties a live
  call to its session and clears the state when the host's session ends.
- The games: `client/components/sunny_side_putt/` (the model layer) and
  `ui/organisms/sunny_side_putt/` (the game); see sunny-side-putt.md.
- `ui/organisms/call_activity/` - the shared UI: the picker (the shelf
  of activities), the stage (the game takes the call's view while the
  participant videos shrink into a strip), and the join pill.

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
   lowest present identity); the last one out ends the session and its
   room state goes with it.

## Testing

- `flutter test unit_test/call_activity` - protocol, session lifecycle
  (launch, join, capacity, election, handoff, inputs) on the in-memory
  transport, `call_activity_ui` - the picker and stage widgets.
- The voice e2e (`integration_test/activities/`) runs two real clients
  through a whole hole when the integration stack (Synapse + LiveKit +
  the auth service, `scripts/integration-server-livekit.sh`) is up, and
  skips cleanly when it is not.
