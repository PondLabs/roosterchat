# Speed log

How long network operations take on this device: every HTTP request an
account makes, and spans for the operations a person waits on (sending a
text, each sync, preparing an attached picture, joining a voice channel).
It lives in memory only, is always on, keeps a fixed number of entries,
and never leaves the device unless someone copies the report and pastes it
somewhere. In developer mode, Settings > Developer > Speed log shows p50
and p95 per operation and per step, and "Copy speed report" copies the
whole log as text.

Code: `rooster/lib/diagnostic/speed_log/` (the log, spans, names, report,
summary, the text, sync and voice join spans) and
`rooster/lib/utils/network/speed_http_client.dart` (the HTTP client under
every `matrix.Client`, and under the `MatrixApi` of Android's background
client, which fetches the events of push notifications). The background
client runs in its own isolate (the Firebase or UnifiedPush handler, or
the background service), so its requests go to that isolate's log, which
the panel does not show. The picture span is in
`rooster/lib/utils/image/preparation/image_preparation.dart`. The panel is
`rooster/lib/ui/pages/settings/categories/developer/speed_log_panel.dart`.

## What is recorded

**Requests**, by `SpeedHttpClient`, the newest 512: method, route template
(`/_matrix/client/v3/rooms/{roomId}/send/{eventType}/{txnId}`), host class
(`homeserver`, `token_service`, `sfu`, `other`), status or error, attempt
number, bytes up and down, time to headers, total, a 429's
`retry_after_ms`, and for a body the moment its last byte was handed over
(`transport` on native, `xhr_upload_onload` on the web) with the upload
rate from there to the answer. A request made inside a span carries the
span's random id (`op=`). An error is one fixed name, never its message
or type: `aborted`, `cancelled`, `timeout`, `socket`, `tls`, `http`,
`client` (any other `ClientException`, the web's network errors among
them) or `other`. A media upload ended by one of its time limits says
which: `upload_stalled` (the connection took no byte of the body for
30 s) or `upload_no_answer` (no answer after the last byte, waited for at
least 150 s and at least the body's time at 100 kB/s; there is no limit
on the total).

**Spans**, the newest 256 finished ones of each operation (each span name
has its own buffer, so a sync round every 30 s never pushes a text send
out) and those still open. At most 16 operations are kept: the names of
`speed_names.dart` fit, and a span of any further operation is dropped and
counted (`N dropped` in the report's `spans (...)` line). A span is one
operation under a random local id, made of named steps on a monotonic
clock, with an outcome (`ok`, `failed`, `incomplete`, `abandoned`,
`cancelled`, `encode_failed`) and the
longest UI frame drawn while it was open.

### Names: a fixed list

Every span, step, value, outcome and error name is a constant in
`rooster/lib/diagnostic/speed_log/speed_names.dart`, and is also listed in
the `all` set of its class there (`SpeedOperation`, `SpeedStep`,
`SpeedValue`, `SpeedOutcome`, `SpeedError`). A name that is not in its
`all` set is written `invalid_name`, even one shaped like the others: that
is how text from a message, a file or a person can never reach the report.
On a step, the numbers under unlisted names are dropped and `invalid_name`
says how many there were (`invalid_name=2`).

To add a name: a constant in its class, the same constant in that class's
`all`, a line here, and the name in `speed_names_test.dart` (it compares
the sets exactly). A branch merged after another one that added names
keeps both sides' entries. `speed_log_doc_test.dart` checks that every
listed name appears in this page.

### `text_send`

`text_send`, a text message, from Send in the composer to the server's
answer. A message with attachments is not one (the file send will have its
own span), nor is a command.

| Step | From | To |
|---|---|---|
| `send` | Send pressed | the room hands the text to the Matrix SDK |
| `echo` | the hand-over | the local echo enters the timeline |
| `echo_painted` | the echo | the end of the next frame drawn; unavailable when no frame comes within 2 s (hidden window) |
| `queue_wait` | the echo | the room's earlier sends have left the SDK's queue (0 when there were none) |
| `request` | the `PUT /send` leaves | its response headers; values `attempt`, `status`, `retry_after_ms` on a 429 |
| `retry` | the same `PUT /send` sent again | its response headers; same values |
| `answer` | the last response headers | the SDK returns the send |
| `key_request` | a key request of the send leaves (`POST /keys/query`, `POST /keys/claim`, `PUT /sendToDevice`) | its response headers; values `attempt`, `status` |
| `outbound_session` | the hand-over, encrypted rooms only | no duration; values `session_created` (1 when no session was ready at the hand-over and the message waited for one to be made, by the send itself or by a preparation still running; 0 when one was ready or was loaded from this device) and `key_requests` (how many key requests the send made) |

Outcome `ok`, or `failed` when the SDK gave up (it waits out a 429 up to a
minute, then marks the message as failed). The time an encrypted room
spends preparing its session falls between `queue_wait` and `request`
(not a step of its own); the composer prepares it ahead, on the first
input and on attaching a file, so `session_created` is usually 0. A
`key_request` with `session_created=0` is a key shared at the send with
a device that appeared since. The room calls into the span through a guard:
a failure in the measurement is dropped (one fixed line in the app's log)
and never stops the send.

### `sync`

`sync`, one round of an account's sync loop, read from the SDK's
`onSyncStatus`: the span starts when the SDK reports it is waiting for the
response, a few milliseconds after the `GET /sync` line in the requests.

| Step | Ends when |
|---|---|
| `server_wait` | the response arrived: the server's wait, where a long poll on an idle account spends up to 30 s |
| `processing` | rooms, events and the database were handled |
| `clean_up` | device keys, encryption and the to-device queue were done |
| `client_work` | the same moment as `clean_up`; it starts where `server_wait` ends, so it is `processing` and `clean_up` together: what the client did, without the server's wait |
| `next_request` | the next round's request left; the span closes here, so its total is one whole round, a retry's back-off included |
| `error` | the round failed (outcome `failed`) |

The total of a round is mostly the long poll; read `client_work` for how
fast this device handles a sync. A round the SDK drops before cleaning up
is `incomplete`; one still going when the account closes is `abandoned`.
The next round opens just before the last one closes, so the report usually
shows one open `sync` span per account.

### `image_prepare`

`image_prepare`, an attached picture made ready to send: its size, a
thumbnail and a blurhash, from the request to the result.

| Step | From | To |
|---|---|---|
| `queue_wait` | the request | one of the two preparation slots is free |
| `header` | the slot | the size and orientation read from the file header; value `bytes` (the file's size) |
| `decode` | the header | the one engine decode, at thumbnail size or smaller, or at full size when the header could not be read; values `width`, `height` (as decoded) and `frames` (more than 1: animated) |
| `encode` | the decode | the thumbnail and blurhash, in the background (native) or by the browser's canvas (web); values `bytes`, `width`, `height` of the thumbnail when one was made |

Outcome `ok`, `failed` when the engine cannot decode the file (it is
then sent as a plain file), `encode_failed` when the thumbnail encoder
failed (the picture is sent with its size, without a thumbnail and a
blurhash), or `cancelled` when the attachment was removed from the
composer before Send (it left the queue, or its result was thrown away).

### `file_send`

`file_send`, a file sent from the composer, from it being attached to the
server's answer for its event (`file_send_trace.dart`). Steps start at
Send unless the table says otherwise.

| Step | From | To |
|---|---|---|
| `attached` | the file attached to the composer | Send; value `bytes` (the file's size) when known |
| `preview_painted` | Send | the end of the first frame drawn after the local picture (or video poster) was decoded; unavailable when no frame came |
| `prepared` | Send | the files handed to the Matrix SDK; values `bytes`, `thumbnail_bytes`, `width`, `height` |
| `echo` | the hand-over | the room's pending event entering the timeline |
| `upload` | the `POST /upload` leaves | its response headers, one per upload (the file, its thumbnail, a new attempt); values `bytes` (sent), `attempt`, `status` |
| `request` | the event's `PUT /send` leaves | its response headers; values `attempt`, `status` |
| `retry` | the same `PUT /send` sent again | its response headers; same values |
| `confirmed` | Send | the SDK returns the event's id, or gives up |

Outcome `ok`, or `failed` when the file did not reach the room.

### `media_show`

`media_show`, a picture of a chat (an attachment, a video's poster) shown
at one level, from its load starting to the end of the first frame drawn
with it (`media_show_trace.dart`). A picture that has a thumbnail makes one
span for the thumbnail and, when opened, one for the full picture; one
already decoded in memory loads nothing and makes none. Value `level` is 1
for the thumbnail (the sender's, or the one the homeserver scales for a
large still picture that has none), 2 for the full picture.

| Step | From | To |
|---|---|---|
| `cache_hit` | the start | the bytes read from this device (the file cache, or the account's own media); values `bytes`, `level` |
| `cache_miss` | the start | this device has nothing; value `level` |
| `download` | the miss | the bytes from the homeserver, after any new attempts; value `bytes`. Its requests are under the span (`/download/` or `/thumbnail/` in the route) |
| `decode` | the bytes | the engine's decode |
| `first_paint` | the start | the end of the first frame drawn with the picture; unavailable when nothing listens to the picture or no frame comes within 2 s |

Outcome `ok`, `failed` when no picture came (after the new attempts, or
the engine could not decode it), or `cancelled` when there was nothing to
show at that level.

### `voice_join`

`voice_join`, a voice join, from the join starting to the microphone
published and the first remote audio. The join runs some steps side by
side, so timed steps may overlap; each has its own start.

| Step | What it times |
|---|---|
| `leave_previous` | the call being left hanging up, beside the rest |
| `output_device` | the picked speakers handed to WebRTC |
| `foci` | finding the call's token service (the well-known) |
| `openid_token` | the OpenID token from the homeserver |
| `sfu_token` | `POST /sfu/get` to the call token service |
| `sfu_livekit_cloud` | the SFU is LiveKit Cloud: when that became known, no duration |
| `sfu_self_hosted` | the SFU is anything else: when that became known, no duration |
| `microphone_early` | a phone's browser opening the microphone before the membership |
| `prepare_connection` | LiveKit's DNS, TLS and region warm-up, when awaited or finished |
| `membership_clear_wait` | waiting for the previous call's clear of our membership |
| `membership_write` | writing our call membership |
| `connect` | the LiveKit connection |
| `connect_websocket` | inside `connect`: from the attempt starting to the signal WebSocket open |
| `connect_join_response` | inside `connect`: from the WebSocket open to the SFU's answer to the join, including LiveKit making the two media connections (peer connections) with it, which it does before it tells the answer |
| `connect_media` | inside `connect`: from the join answered to the media connection (the primary peer connection) connected |
| `microphone_options` | the microphone's capture options (the DSP's bounded wait included) |
| `microphone_open` | opening the microphone capture during the connection |
| `sfu_region` | unavailable: the SFU reported no region |
| `sfu_region_other` | the SFU reported a region: when it became known, no duration |
| `microphone_published` | from connected to the microphone published; unavailable when it was not (denied, no device) or not within 30 s |
| `first_remote_audio` | from connected to someone else first heard; unavailable when nobody spoke within 30 s |

The three `connect_*` steps come from LiveKit itself (`Room.onConnectStep`,
a hook in our copy of the SDK) and are those of the connection attempt that
ran last: when LiveKit tries another region, or the join connects again
after the SFU refused a held call token, the earlier attempt's moments are
dropped. A step whose moments did not both come (the connection failed
before) is `unavailable`. Together they fit inside `connect`, which also
holds what LiveKit does before and between its attempts.

The span says only whether the SFU reported a region (`sfu_region_other`)
or not (`sfu_region` unavailable), never which: the region is the server's
own text, and a self-hosted SFU can put anything there. Outcome `ok` once the
microphone and the remote audio are settled, or `failed` when the join
failed.

A step the app cannot time is written `unavailable`, never guessed.

## What is never recorded

No message text, file names, user, room or event ids, URLs, hosts, query
strings, tokens or keys: not in memory, not in a log line, not in the
report. Routes are kept only as templates and hosts only as a class; an
unstable prefix (`org.matrix.msc3575`) is kept only right after
`/_matrix/client/unstable/`, `/_matrix/media/unstable/` or
`/_matrix/federation/unstable/`. A template keeps only the fixed words of
`route_template.dart` (the Matrix, LiveKit and call token service APIs:
the warm-up's `GET /healthz` reads as such), and on a host of class
`other` not even those: every segment there is `{param}`, but for the
Matrix well-known lookup. A span remembers which requests it already
sent only as hashes salted per span, forgotten when it finishes. The
transaction id that lets the text span see its echo stays in a local
variable of the send and is only compared with the echo's. Every name in
a span comes from the fixed list in `speed_names.dart` (see "Names: a fixed
list"); anything else is written `invalid_name`.

## Reading the report

```text
Rooster speed report
clock: monotonic, +seconds since the log started

summary (p50 and p95 of the finished spans that ended ok):
sync ok=2/2 p50=30056ms p95=30156ms
  server_wait n=2 p50=30028ms p95=30053ms
  ...
  client_work n=2 p50=21ms p95=88ms
  ...
text_send ok=1/1 p50=44ms p95=44ms
  send n=1 p50=1.1ms p95=1.1ms
  ...

requests (2, newest 512 kept):
+0.561s PUT /_matrix/client/v3/rooms/{roomId}/send/{eventType}/{txnId} homeserver status=429 attempt=1 op=8e7f3b06b47dbfbd up=0 down=78 headers=0.2ms total=1.5ms retry_after_ms=30
+0.595s PUT /_matrix/client/v3/rooms/{roomId}/send/{eventType}/{txnId} homeserver status=200 attempt=2 op=8e7f3b06b47dbfbd up=57 down=22 headers=0.6ms total=0.8ms handed_over=0.3ms(transport) to_answer=0.3ms up_rate=194kB/s

spans (1 finished, newest 256 of each operation kept, 1 open):
+0.556s text_send op=8e7f3b06b47dbfbd total=44ms outcome=ok longest_frame=unavailable
  send +0.0ms 1.1ms
  echo +1.1ms 1.8ms
  echo_painted +2.8ms 5.7ms
  queue_wait +2.8ms 0.0ms
  request +4.8ms 0.2ms attempt=1 status=429 retry_after_ms=30
  retry +39ms 0.6ms attempt=2 status=200
  answer +39ms 4.1ms
```

- **Summary**: per operation, `ok=` how many of the finished spans ended
  `ok`, then p50 and p95 of their totals; under it each step, with `n=`
  the timed samples and `unavailable=` the ones that could not be timed.
  Percentiles are by nearest rank (p95 of 20 samples is the 19th). Failed
  and dropped spans are counted but left out of the percentiles.
- **Requests**: one per line, `+seconds` from the log's start. `op=` ties a
  request to the span that made it: above, the 429 and the retry 34 ms
  later are both the text send's.
- **Spans**: the span line, then each step as `name +start duration`,
  `start` counting from the span's start. Steps measured independently may
  overlap (`echo_painted` and `queue_wait` both start at the echo). The
  header line ends with `, N dropped: more than 16 operations` when spans
  were dropped.
- To know how soon a text left after Send (G2 in the speed work): the
  `request` step's start. How long the server took: its duration. A
  long poll is the `sync` `server_wait` step, not a slow server; the
  client's share of a round is `client_work`.
- The panel shows the same summary; the copied report is what to attach to
  an issue.
