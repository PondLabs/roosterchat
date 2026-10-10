# Landing page screenshots

Every screen on the landing page (`website/`) is the real web app, captured in headless Chrome while a made-up crew uses it. The homeserver, LiveKit and the crew all run on this machine: nobody in the screenshots is a real person, and nothing goes out to the internet. The phone and laptop around them (`website/media/devices/`) are drawings in SVG.

## Pieces

| File | What it does |
|---|---|
| `setup.sh` | One time: Synapse in a virtualenv, LiveKit's server, a self-signed certificate, Playwright, the crew's media (`make_media.py`, `media.mjs`) and a copy of the web build. Everything goes in `$ROOSTER_SHOTS`, `/tmp/rooster-shots` by default. |
| `homeserver.yaml` | Synapse's config. The server is `the-coop.social`, a name that exists only here. |
| `services.sh` | Starts Synapse, LiveKit, the JWT stand-in and a static server for the app; `services.sh stop` stops them. |
| `jwt-service.mjs` | Stands in for lk-jwt-service. Rooster only takes an https focus, and lk-jwt-service would look the made-up server up in DNS; this one checks OpenID tokens with the local Synapse and signs tokens for LiveKit's dev keys. |
| `seed.mjs` | The crew (Maya, Theo, Priya, Jonas, Bia, Kenji, Lou and Rafa), Maya's houses, The Coop's channels, an evening of chat in #general with a poll, a DM, and four soundboard sounds. |
| `make_media.py`, `media.mjs`, `kart.html` | Synthesized voices for the fake microphones, four songs for the DJ booth, the soundboard clips, the avatars (emoji animals on palette colours), and Kart Night, the made-up game Jonas streams. |
| `crew.mjs` | One Chrome per person, each with their own profile and fake microphone, and what drives the app: logging in, joining the Lounge, muting, opening a person's menu in the call. |
| `capture.mjs` | Sets the call up (who talks, who's muted, Priya on the decks, Jonas sharing) and captures Maya's screens on a laptop and a phone, and Priya's at the decks. With `DEBUG=1` it says which menu each call tile opened. |
| `export.py` | Crops and encodes the captures into `website/media/shots` (WebP and AVIF, at the two widths each is shown). |

## Taking them again

Build the web app with its base at `/`, then:

```sh
cd rooster
dart run scripts/codegen.dart
./scripts/prepare-web.sh
flutter build web --release --dart-define BUILD_MODE=release --dart-define PLATFORM=web \
  --dart-define ENABLE_GOOGLE_SERVICES=false --dart-define FLUTTER_WEB_CANVASKIT_URL=canvaskit/
cd ..
docs/brand/screens/setup.sh
docs/brand/screens/services.sh
node docs/brand/screens/seed.mjs        # once, on a fresh database
node docs/brand/screens/capture.mjs
docs/brand/screens/export.py
```

It needs `google-chrome`, Node, Python 3, `ffmpeg`, ImageMagick (`magick`), `avifenc` and `openssl`. `prepare-web.sh` needs the Rust toolchain; the files it builds (vodozemac, the LiveKit E2EE worker, `audio_dsp.wasm`) can also be taken from the published app at `pondlabs.github.io/roosterchat/app/`.

Then look at every capture in `$ROOSTER_SHOTS/caps` before exporting: who is talking depends on where the synthesized voices are when the shutter goes, and the page's alt text describes what each picture shows.

## Things to know

- A browser profile's first login takes minutes, since encryption is set up in wasm, and seven at once take longer. Profiles are kept in `$ROOSTER_SHOTS/profiles`, so later runs open in seconds.
- Seven Flutter apps run at once. `capture.mjs` keeps the tabs it isn't capturing behind a blank tab: Flutter stops drawing them and their call goes on.
- Jonas's screen share is a looping video of `kart.html`, handed to the app by a stand-in `getDisplayMedia`. It is served with the app, so the stream isn't cross-origin.
- The app is driven through its accessibility tree, by the labels a screen reader reads, and by position where a control has none (the space rail, the call tiles). A redesign can move those; `capture.mjs` says which step it was on.
- The notice in "Calls that fix themselves" (`card-health`) was a real repair, caught live on a busy machine. Nothing stages it, so `export.py` leaves that image alone unless `$ROOSTER_SHOTS/caps/health.png` exists.
