# Soundboard in a call

A press reaches the call two ways at once.

1. **The press itself**, for Rooster: a `chat.commet.soundboard.v1` message
   on the LiveKit data channel (Matrix to-device `chat.commet.soundboard.play`
   when there is no LiveKit room). Every Rooster client fetches the sound and
   plays it locally, in sync by the sender's clock, at the listener's own
   volumes (below). The emoji on the sender's avatar comes from this too.
2. **A track**, for every other client (Element Call, anything that does
   not know the press message): our own presses mixed into one audio track
   named `commet-soundboard`
   (`MatrixLivekitVoipStream.soundboardTrackName`), published on the first
   press and kept until the call ends. Such a client plays it as the
   presser's audio.

Rooster never subscribes to a `commet-soundboard` track and makes no stream
or tile of it (`_isSoundboard` in `matrix_livekit_voip_session.dart`), so
nobody hears a sound twice. Builds from before this change take the track
for the presser's voice and do hear it twice.

The track is separate from the DJ booth's `commet-dj-music`, so turning the
music down never touches the sounds, and the other way round.

## Sending

| Where | How |
|-------|-----|
| `client/components/soundboard/soundboard_engine.dart` | `SoundboardBroadcast`: the engine hands it our own presses (`localTrigger`) and stops a press cut short (restarted, or pushed out by newer ones). Remote presses never go there. |
| `client/matrix/components/soundboard/native/soundboard_broadcast_native.dart` | Desktop (Linux, Windows): the clip is decoded by `rust/dj_audio` (`clip.rs`), interleaved, and handed to the board (`board.rs`), which mixes overlapping presses. flutter-webrtc's `roosterCreateMusicTrack` custom source pulls from it every 10 ms, as it does for the DJ booth's player. |
| `client/matrix/components/soundboard/web/soundboard_broadcast_web.dart` | Browser: each press plays into one `MediaStreamAudioDestinationNode`, whose stream is the track. |
| `ui/organisms/soundboard/soundboard_call_controller.dart` | Creates the broadcast when the call has a LiveKit room, and unpublishes it when the call ends. |

Sent at the sound's own level (`SoundboardSound.gain`: loudness
normalisation times the sound's volume), never at the presser's listening
volume. Opus at up to 96 kbps with DTX on, since the track is silent between
presses. Like the DJ booth's music, the custom source writes its audio
options onto the processing it shares with the microphone, so they are the
microphone's own, and `restoreMicrophoneProcessingAfter` runs for it as for
any other local audio publication (`docs/voice-audio-processing.md`).

Not sent from macOS or Android: neither has the custom source (the Rust
library is only built for Linux and Windows), so their presses still reach
only Rooster.

## Listening

Each listener has, apart from each other:

- the **soundboard volume** (`soundboard_volume`, the soundboard popover and
  settings), for every sound;
- a **per-person sound effects volume** (`call_soundboard_volume:<userId>`,
  0 to 100 %), in the person's tile menu under their voice volume
  (`SoundboardUserVolumeSlider`), multiplied with the one above;
- their **voice volume** and the **DJ music volume**, which do not affect
  sounds.

Deafening silences sounds too (`SoundboardCallController.listenerVolume`).
