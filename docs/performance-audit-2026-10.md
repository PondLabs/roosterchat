# Performance, stability and parity audit, October 2026

Baseline: `257dc683` (the merge of #204, after v1.15.1). Audit date:
2026-10-08. The changes are in the accompanying pull request, one commit per
fix. The earlier audit is `docs/stability-audit.md`; this one does not repeat
what it fixed.

The brief: what the user feels, on every platform alike. The audit read the
startup path, the sync and room-list code, the chat timeline, the voice
rooms, the web delivery, the release pipeline and the platform gates, and
confirmed each finding in the code before changing it. The arm64 release
builds are described in `docs/updating.md`.

## What was slow, and what changed

| Where | Found | Now |
| --- | --- | --- |
| Web first load | tiamat declared a 23.7 MB Noto Color Emoji font nothing referenced; the engine downloaded it (7.7 MB gzipped, almost half of the first-frame payload) and every desktop and Android bundle carried it. Roboto was fetched again from fonts.gstatic.com because the bundled family was named `RobotoCustom`. The page waited for the window's `load` event (the 1.5 MB splash animation included) before fetching `main.dart.js`, and CanvasKit only after that had run. | The font is gone, Roboto is `Roboto`, Flutter's own `flutter_bootstrap.js` starts the app and CanvasKit together, the splash still shows first, the voice script is deferred. |
| Web, every frame | Every `Tile` wrapped its content in a `BackdropFilter`, an identity one without glass: a readback of everything behind the tile per frame, for the sidebar, the panels and the chat chrome. | Only a glass theme gets the filter. |
| Desktop startup | A GitHub request for the latest release ran before anything else, and every launch waited for it (20 s on a bad network). `preferences.init()` ran twice. | The check runs beside initialisation, bounded to five seconds; the load is shared. |
| Startup, every platform | The file cache loaded every row to log a count, on the isolate the Matrix database shares. vodozemac loaded before any account's database opened, and the databases opened one after another. The SDK logged at verbose and kept every log event for ever. Every space decoded and quantised its avatar at start and on every update. On the web the first frame could show untranslated strings. | A count; databases open together while vodozemac loads; the SDK keeps the app's level and the newest thousand events; a space's scheme is taken once per avatar; translations are awaited. |
| Every sync | `hasRoom`/`getRoom` scanned the room list (with an exception per miss) for every room of every sync, quadratically; a space told its listeners once per room the sync touched; rooms sync dropped were forgotten with their subscriptions alive; typing notices rebuilt every channel list. | Rooms and spaces are indexed by id; one space update per sync; dropped rooms are closed; ephemeral-only updates are skipped. |
| Chat timeline | Three or four read-marker POSTs per incoming message. Every visible entry rebuilt its context menu on every rebuild (three walks of the spaces for emoticon packs, the recents sorted twice). The entry key list was scanned per built child per rebuild. `MediaQuery.of` made the timeline rebuild per frame of the keyboard animation. Reply quotes re-fetched their event on every scroll-in; `plainTextBody` re-parsed HTML on every call. | One request per newest event; the menu is made once per event, the space walk cached; an index; `MediaQuery.sizeOf`; fetched events kept and shared; text parsed once. |

## What could break, and what changed

| Found | Now |
| --- | --- |
| `imageProviderToImage` never completed on error and never removed its listener: a sticker send or a Linux notification hung for ever on one bad image, and every image fetched this way stayed decoded (and animating) for the life of the app. The lightbox did the same for every image viewed and never disposed its controllers. | Errors complete, listeners come off, timeouts where a flow waits; notifications show without a picture that failed. |
| The composer stayed faded and dead for the rest of the visit when preparing a message threw (an attachment that could no longer be read). | Reset in a `finally`; such attachments are skipped. |
| Every `getTimeline()` made a new SDK timeline (five subscriptions) and replaced the room's without closing the old: one per search keystroke, per jump, per album open, per "mark as read". | Timelines have owners that close them. |
| A room wrapper cancelled one of its four SDK subscriptions on close; sync-dropped rooms were never closed; after leave and rejoin the old wrapper added to a closed stream on every sync. | All four cancelled; dropped rooms closed; guarded. |
| An open chat of a room sync dropped rendered every message as an error box. | The selection clears; a message whose room is gone is plain text. |
| Panels, a room entry's typing timer, the composer's controllers and focus nodes, the quick access menu's listener, the chat's streams and thread timelines, the overlay's controller: never released. | Released. |
| The About page threw on a Linux session without `XDG_SESSION_TYPE`; a room named `#` threw from its sidebar entry; a second launch could wait for ever on a main instance that accepted the socket and said nothing; a login that threw stopped silently. | Guarded, bounded, reported. |
| Voice: a hang-up waited unbounded on a membership write; a hang-up step that threw left the DSP watchdog ticking for ever; coming back after a LiveKit outage retried the state write every second; joining fetched the token and the SFU with no timeout; two joins of one room overlapped; a hang-up mid-restart left the microphone on; a full reconnect played the leave sound and dropped deafened badges; on the web the join waited unbounded for the 11 MB DSP wasm. | Bounded, cancelled, backed off, memoised, stopped, quiet, bounded. |
| The proxy worker fetched upstreams with no timeout or error handling; the Linux arm64 CEF download died when the CDN cut it. | Bounded with CORS errors; resumable. |

## Parity

| Platform gap | Now |
| --- | --- |
| The web had no notifications at all, and no settings tab to say so. | The browser's Notification API is a notifier like the desktop ones, with the settings tab, toggles and a permission button. |
| Windows had the notification toggles and no tab to reach them (and a page that said notifications were unsupported). | Shown. |
| The web saved the microphone pick and ignored it; 1:1 calls could not share the screen in the browser. | Used; shared. |
| An http page (not localhost) died at startup with an account registered, or failed login with a message about storage. | Opens; voice rooms say they need HTTPS. |
| The web app opened two IndexedDB connections per database and waited on `storage.persist()` (a prompt in Firefox). | One; not awaited. |

Still different, deliberately or for lack of a platform path, and left for later
with the evidence in the audit: no Android foreground service of type
`microphone` for a call (a backgrounded Android app sends silence; needs a
device to verify), no "reconnecting" state in the call UI (a dead call looks
connected for up to three minutes), macOS lacks the fullscreen, window and
shortcut settings that the other desktops have (`WindowManagement.init`
returns early there; the Rust library is not built for it), the soundboard
track and the DJ booth need the Rust library (not built for Android and
macOS), and `BuildConfig.ANDROID` and friends still come only from the
`PLATFORM` dart-define.

## Verification

Each fix was followed by `dart analyze` on the files it touched, the unit
tests of the area (`flutter test unit_test/...`) and, at the end, the whole
suite, the Python tool tests (`python3 -m unittest tools.*`), the voice DSP
contract checker and a web release build. The Linux arm64 build, the arm64
installers and the arm64 lock were run on GitHub's arm64 runners from the
branch (`desktop-build.yml` dispatched with `["linux-arm64"]`), and the
real arm64 CEF archives were verified, staged and stripped with
`tools/cef_runtime.py` locally. Nothing here was measured on a device: the
numbers above are sizes and request counts read from the code and the live
deployment, not frame times; the stability workflow's CI measurements are
the place to watch them move.
