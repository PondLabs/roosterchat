# Source extensions

The app knows no site. It takes audio files from the user's disk, and
(for the soundboard) links straight to an audio file; for a link to a page
(a video, a post, a sound's page) it asks a **source extension**: a program
the user installs on their desktop client, which says what the link holds
and downloads its audio. Two parts of the app use them:

- The **DJ booth** (`docs/dj-booth.md`) queues what a link holds, and plays
  and publishes each song like a local file.
- The **soundboard** (a Space's settings, "Add sound") takes the first
  thing a link holds, shows up to a minute of it in the trim editor, and
  stores the part the admin keeps (at most 15 s) as Ogg Opus on the
  homeserver. Nobody else in the Space needs the extension: they play the
  stored sound.

Extensions are desktop only (Linux, Windows). They are not made or shipped
with Rooster, and one extension may serve both parts: it says which in its
manifest (`uses`), and each request says which it is for (`for`).

## Writing one

An extension only answers two questions: what a link holds (`resolve`) and
"download this one" (`fetch`). It writes a file and is done: the app does
the rest (queueing, streaming, trimming, loudness, size limits). The
yt-dlp extension (`RamAddict/dj-ytdlp-source`, both uses) is a worked
example in Deno, but anything the manifest can start works.

## Package

A `.zip` with `rooster-extension.json` at its root, next to whatever the
extension runs (scripts, data). The names from before the renames,
`cockhouse-extension.json` and `roscord-extension.json`, are still read, so
older extensions keep working. Installed from a file the user picks or an
`https://` link they paste, into `<app support>/dj-extensions/<id>/`. The
app records where it came from, so it can be installed again from there to
update it.

```json
{
  "protocol": 1,
  "id": "org.example.music",
  "name": "Example music",
  "version": "1.0.0",
  "description": "One line shown in the install prompt and the list.",
  "homepage": "https://example.org/music-extension",
  "hosts": ["example.org", "music.example.net"],
  "hint": "Paste an Example link",
  "uses": ["dj", "soundboard"],
  "downloads": [
    {
      "id": "deno",
      "name": "Deno",
      "size": "45 MB",
      "files": {
        "windows-x64": {
          "url": "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip",
          "unzip": "deno.exe"
        },
        "linux-x64": {
          "url": "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip",
          "unzip": "deno"
        }
      }
    }
  ],
  "run": {
    "command": "{dep:deno}",
    "args": ["run", "--allow-all", "--no-prompt", "{dir}/main.ts"]
  }
}
```

- `protocol`: `1`. Anything else is refused.
- `id`: 3 to 64 characters of `a-z 0-9 . _ -`, unique. Installing the same
  id again replaces the installed one.
- `hosts`: the links it takes. A link's host matches an entry equal to it or
  ending in `.` + it (`www.example.org` matches `example.org`). `"*"` takes
  any link no other extension claims.
- `hint`: the DJ booth's add bar placeholder while this extension is the
  only one installed for it.
- `uses`: what it serves, `"dj"` and/or `"soundboard"`. Without it, `["dj"]`
  (extensions from before the soundboard used them). Values the app doesn't
  know are skipped; a manifest left with none is refused. Links are only
  sent to extensions serving what they are for: a soundboard-only extension
  never sees the booth's links, and the other way round.
- `downloads`: programs fetched at install time, after the user agrees, with
  progress shown. Platforms are `windows-x64`, `linux-x64` and
  `linux-arm64`; an extension with a download that has no file for this
  platform can't be installed here. `unzip` names the file to take out of a
  `.zip` download; without it the download is the program. `sha256`
  (lowercase hex) is checked when present. Each program lands at
  `<dir>/deps/<id>` (`.exe` added on Windows) and is made executable.
- `run`: how to start the extension. `{dir}` is the extension's folder,
  `{dep:<id>}` the path of a download. The booth appends the verb and the
  request (below).

The install prompt says the extension runs a program with the user's
permissions and lists the downloads with their sizes. Nothing is fetched
before the user agrees.

## Protocol

One process per request. The booth starts `command args… <verb> <request>`,
where `<request>` is one JSON object as a single argument, and reads JSON
objects from the process's stdout, one per line. Other lines are ignored;
stderr is kept for the log. stdin is empty. The working directory is
`{dir}`. On Windows the process gets a console with no window
(`CREATE_NO_WINDOW`), which whatever it starts inherits, so nothing in the
tree flashes a window; that is also why the request is an argument and not
stdin or the environment.

Every request carries `"protocol": 1`, `"data"`: a folder the extension
may keep things in (`<dir>/data`, created before the first request), and
`"for"`: `"dj"` or `"soundboard"`, what the answer is for (clients from
before the soundboard used extensions leave it out: read that as `"dj"`).
`<dir>/deps` is writable too, so a download can update itself. Fields an
extension doesn't know are to be ignored: later versions of the app may
add some.

The process is killed when it runs over its time (below). On Windows it runs
in a job object of its own, and the kill ends the whole job: whatever it
started goes too. A program it leaves running after it has ended normally
(an updater, say) is left alone. On Linux only the process gets the
signal, so an extension that starts other programs should end them when it
goes.

### `resolve`

What a pasted link holds. 90 seconds.

```json
{"protocol": 1, "data": "/…/dj-extensions/org.example.music/data",
 "for": "dj", "url": "https://example.org/album/123"}
```

Answer:

```json
{"tracks": [
  {"source": "https://example.org/track/1", "title": "Song",
   "artist": "Artist", "durationMs": 215000,
   "thumbnail": "https://example.org/art/1.jpg", "label": "Example"}
]}
```

or `{"error": "Nothing playable in that link"}`.

- `source` (required, at most 900 characters): whatever the extension wants
  back in `fetch`. It travels to everyone in the call, so it must not carry
  anything private.
- `title` (required), `artist`, `durationMs`, `thumbnail` (`https://`).
- `link`: the page to open for the song, when it isn't `source`. A track
  with a `link` keeps the title and artist given here; one without has them
  replaced by what `fetch` reports.
- `label`: at most 16 characters, shown on the song's chip in the queue.

### `fetch`

Downloads one song's audio. 10 minutes.

```json
{"protocol": 1, "data": "/…/data", "for": "dj",
 "source": "https://example.org/track/1",
 "directory": "/…/dj-songs", "name": "3f2a9c…", "trusted": true}
```

The song goes to `<directory>/<name>.<ext>`, written in place: the booth
plays it while it grows, so no temporary name and no rewriting once done.
Before the first byte:

```json
{"started": {"path": "/…/dj-songs/3f2a9c….webm", "size": 3481234,
  "durationMs": 215000, "title": "Song", "artist": "Artist",
  "thumbnail": "https://…", "audio": "opus 132 kbps, 48 kHz stereo"}}
```

`path` is required; `size` lets the player tell a slow download from the
end of the file, so it is the exact size in bytes or left out, never an
estimate. `audio` goes in the log. When the whole file is written:

```json
{"done": {"path": "/…/dj-songs/3f2a9c….webm"}}
```

with the same `path` as `started` (an extension that ends up writing another
file sends an error instead), or `{"error": "why"}` at any point. A process
that ends without `done` failed. The booth reads stdout until it closes, so
helper programs the extension starts must not hold on to it.

The player reads Opus in WebM or Ogg, AAC in MP4 (fragmented too), MP3,
Vorbis, FLAC and WAV. MPEG-TS it can't.

`trusted` is false when the song came from another client's booth state (a
DJ who took over the decks fetches the queue the previous DJ built). Such a
source was not checked by this user, so an untrusted fetch must only reach
sites the extension knows, never fetch an arbitrary page. Before asking,
the booth refuses an untrusted `http(s)` source whose host is not public
(`localhost`, private and link-local addresses).

## In the booth

- Queued songs from an extension have the source
  `ext:<extension id>:<source>`. A DJ without that extension can't play
  them, and the booth skips them with a notice.
- Sources queued by clients older than extensions (plain links) go to the
  first installed extension serving the booth whose `hosts` match, else the
  first installed one serving the booth.
- Local files are `file:<id>`, known only to the DJ who added them (the path
  stays on their machine; the file name, as the title, is what the room
  sees). Another DJ skips them. A DJ can't hand over the decks while one is
  playing.

## In the soundboard

An admin adds a sound from a file on their computer or a pasted link:

1. A link goes to an extension serving the soundboard that names its host
   in `hosts`; else, when its path ends in an audio file extension (`.mp3`,
   `.ogg`, `.m4a`, …), the app downloads it itself; else to an extension
   serving the soundboard with `"*"`; else the app downloads it itself and
   refuses it unless the answer's `Content-Type` is audio or video. So
   without any extension, links to audio files still work.
2. With an extension: `resolve` with `"for": "soundboard"`. Only the
   **first** track is used, so answer with just one (a playlist link: its
   first entry, without listing the rest). `title` becomes the suggested
   name. `durationMs` matters here: past a minute, the app asks where to
   start.
3. `fetch` with `"for": "soundboard"`, `"trusted": true` (the admin pasted
   the link) and a temporary `directory`. The app waits for `done` and
   doesn't read the file while it grows, so writing it in place is optional.
   The whole file is downloaded: at most 200 MB, and the app deletes it once
   the sound is added or abandoned.
4. The app decodes a window of at most 60 s, starting at the link's `t=` /
   `start=` when it has one, or where the admin says. It reads what the DJ
   player reads (above); video tracks in MP4 or WebM are ignored, so an
   extension for a video site can hand over the video file when the site
   has no audio-only one.
5. The admin trims the selection to at most 15 s. The app fades its ends
   over 5 ms, measures its loudness (`soundboard_normalizer.dart`), encodes
   it to Ogg Opus (96 kbps, `rust/dj_audio/src/clip.rs`), checks it is under
   1 MB, and uploads it. The stored sound keeps the pasted link as its
   `source_url`, for provenance; a file's path is not kept.

Adding sounds needs the desktop app: web and Android play sounds but can't
add them.
