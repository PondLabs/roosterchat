# Speed log

How long network operations take on this device: every HTTP request an
account makes, and spans for the operations a person waits on (sending a
text, each sync). It lives in memory only, is always on, keeps a fixed
number of entries, and never leaves the device unless someone copies the
report and pastes it somewhere. In developer mode, Settings > Developer >
Speed log shows p50 and p95 per operation and per step, and "Copy speed
report" copies the whole log as text.

Code: `rooster/lib/diagnostic/speed_log/` (the log, spans, report, summary,
the text and sync spans) and `rooster/lib/utils/network/speed_http_client.dart`
(the HTTP client under every `matrix.Client`). The panel is
`rooster/lib/ui/pages/settings/categories/developer/speed_log_panel.dart`.

## What is recorded

**Requests**, by `SpeedHttpClient`, the newest 512: method, route template
(`/_matrix/client/v3/rooms/{roomId}/send/{eventType}/{txnId}`), host class
(`homeserver`, `token_service`, `sfu`, `other`), status or error type,
attempt number, bytes up and down, time to headers, total, a 429's
`retry_after_ms`, and for a body the moment its last byte was handed over
(`transport` on native, `xhr_upload_onload` on the web) with the upload
rate from there to the answer. A request made inside a span carries the
span's random id (`op=`).

**Spans**, the newest 256 finished ones of each operation (each span name
has its own buffer, so a sync round every 30 s never pushes a text send
out; at most 16 operations) and those still open. A span is
one operation under a random local id, made of named steps on a monotonic
clock, with an outcome and the longest UI frame drawn while it was open.
Every span, step, value and outcome name is a constant in
`speed_names.dart`.

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

Outcome `ok`, or `failed` when the SDK gave up (it waits out a 429 up to a
minute, then marks the message as failed). The time an encrypted room
spends preparing its session falls between `queue_wait` and `request`
(not yet a step of its own).

`sync`, one round of an account's sync loop, read from the SDK's
`onSyncStatus`: the span starts when the SDK reports it is waiting for the
response, a few milliseconds after the `GET /sync` line in the requests.

| Step | Ends when |
|---|---|
| `response` | the response arrived (a long poll waits here up to 30 s) |
| `processing` | rooms, events and the database were handled |
| `clean_up` | device keys, encryption and the to-device queue were done |
| `next_request` | the next round's request left; the span closes here, so its total is one whole round, a retry's back-off included |
| `error` | the round failed (outcome `failed`) |

A round the SDK drops before cleaning up is `incomplete`; one still going
when the account closes is `abandoned`. The latest round stays open until
the next request, so the report usually shows one open `sync` span per
account.

A step the app cannot time is written `unavailable`, never guessed.

## What is never recorded

No message text, file names, user, room or event ids, URLs, hosts, query
strings, tokens or keys: not in memory, not in a log line, not in the
report. Routes are kept only as templates and hosts only as a class. A
span remembers which requests it already sent only as hashes salted per
span, forgotten when it finishes. The transaction id that lets the text
span see its echo stays in a local variable of the send and is only
compared with the echo's. Names in spans must match `[a-z][a-z0-9_]*`;
anything else is written `invalid_name`.

## Reading the report

```text
Rooster speed report
clock: monotonic, +seconds since the log started

summary (p50 and p95 of the finished spans that ended ok):
sync ok=2/2 p50=56ms p95=156ms
  response n=2 p50=28ms p95=53ms
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
  overlap (`echo_painted` and `queue_wait` both start at the echo).
- To know how soon a text left after Send (G2 in the speed work): the
  `request` step's start. How long the server took: its duration. A
  long poll is the `sync` `response` step, not a slow server.
- The panel shows the same summary; the copied report is what to attach to
  an issue.
