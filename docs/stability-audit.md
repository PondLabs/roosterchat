# Daily-use stability and performance audit

Baseline: `a620ba7e3d9d8f561fbb4a8d9ca1e6854527e929` (v1.4.0).
Audit date: 2026-10-03. Changes are in the accompanying pull request.

## Confirmed defects and corrections

The following failures were reproduced against the original implementation,
then exercised with the corrections in place:

| Resource / trigger | Original behavior | Correction / regression |
| --- | --- | --- |
| Text scaling after repeatedly closing a view | Global preferences subscription retained disposed states; subsequent changes raised `setState() called after dispose()` | Cancel subscription on disposal; mount/unmount 30 times, then change preference |
| Safe-area focus events after closing a view | Global focus subscription remained registered | Cancel subscription; assert the event bus has no listener after each of 30 cycles |
| Async task completed after removal, or removed before delayed cleanup | Future callback or five-second timer added to a closed stream | Track disposal and cancel the timer; exercise both completion orders |
| Download removed while running or after completion | Status stream stayed open and delayed removal still ran | Close the stream, cancel the timer, ignore late updates; reproduce both completion orders |
| Presence cache receiving 10,000 distinct keys | Declared capacity was not enforced | Evict oldest writes immediately; retain 50 entries and observe 9,950 removals |
| Logging 20,000 distinct messages | All messages remained in the global in-memory list | Retain at most 2,000 entries; preserve consecutive-message coalescing |
| Reopening a chat timeline 50 times | Global jump subscription retained closed timeline states; scroll controllers were not disposed | Release subscriptions and both replaced/current controllers; verify disposal after every cycle |
| First render/reference audio callbacks on macOS | Allocation-free processing test found two allocations | Initialize both mutexes in the DSP constructor; retain the zero-allocation assertion |

Presence shutdown now releases SDK subscriptions, the global idle observer,
the expiry timer and stream. The client invokes it before disposing its SDK.
Late presence lookups and timeline callbacks check whether their owner is still
alive. Cache expiry is checked on reads as well as periodic cleanup; cleanup no
longer waits 200 ms for every entry. Presence explicitly retains up to 2,000
recent users rather than inheriting the utility's small default capacity.

The macOS failure matches Rust's [pthread mutex implementation](https://github.com/rust-lang/rust/blob/1.99.0/library/std/src/sys/sync/mutex/pthread.rs),
which allocates its backing mutex on first lock. Constructor initialization
moves that allocation before the audio callbacks. The corrected macOS run passes
the same zero-allocation assertion; no test threshold is relaxed.
The background model's shared slot is initialized before spawning its loader
too. A separate cold-callback test polls it with inference disabled, isolating
mutex initialization from tract's permitted inference allocations.

Review also found that a video file resolving after its preview closes could
update a closed playback controller or open a disposed player. The preview now
owns and cancels its download-progress subscription and checks its lifetime
after asynchronous operations and before reporting errors/cleanup. A real-media
backend integration regression closes a preview with resolution still pending,
checks immediate subscription release, then completes the request. Unlike the
table's failures, this case has not been replayed against a pre-fix application;
its post-fix integration result is recorded in the PR.

That integration regression exposed a separate native process termination on
the macOS runner during accelerated video-output initialization, before file
resolution. Web, Linux and Windows pass the same scenario. CI now retains macOS
crash reports and stderr and supports focused platform runs. The application
probes the OpenGL pixel format, context and texture cache required by the locked
media_kit_video backend before its native forced unwraps. Capable Macs keep
hardware rendering; unavailable contexts use the existing software backend.
Five regression tests cover the renderer decision, including native-probe
errors and other platforms. Native crash diagnosis and the latest post-fix
execution results are recorded in the PR; compilation alone is not validation
of this media scenario.

## Repeatable workload

`rooster/unit_test/stability/timeline_workload_test.dart` uses actual Matrix event
conversion and chat widgets with 551 deterministic events, replies, reactions,
and link previews. Storage and networking are substituted. Each cycle mounts a
timeline, scrolls in both directions, unmounts it, and checks for exceptions and
retained listeners. Desktop (1440×900) and mobile (390×844) layouts are explicitly
selected; resizing a desktop browser alone does not emulate a mobile browser.

The widget test runs ten cycles. The integration workload runs twenty cycles
inside the native application in profile mode and Chrome in release mode.
Flutter `watchPerformance` records build/raster frame measurements where the
platform exposes them, separately for desktop and mobile layouts. Samples
after each cycle report native process RSS or
Chromium JS heap usage. CI stores the original logs and collected measurements
as `stability-linux`, `stability-windows`, `stability-macos`, and `stability-web`.

`tools/stability_report.py` preserves failures, skips, missing inputs and test
completion status. It does not treat an incomplete log as a successful run.
Widget-host elapsed time includes test overhead and is **not** an FPS or startup
benchmark. RSS includes native allocations and Flutter caches; JS heap excludes
GPU/native browser memory and may be unavailable. These short samples cannot
prove the absence of leaks, and no absolute speed or memory threshold has been
invented without an established runner baseline.

## Validation and CI coverage

Existing baseline CI runs passed the full Flutter/Rust suite, Web voice DSP,
desktop release builds, Linux integration against Synapse, static analysis and
Web publication. Those results validate the original revision only.

Local reproduction used Flutter 3.41.9 / Dart 3.11.5 on an Android ARM64 host with
the patched Linux test runtime. The full suite passed: 1,215 tests, nine skips,
zero failures. Eight skips require the native DSP library/fixture and one
requires native media playback. The Rust DSP itself passed all 75 tests,
including its allocation-free processing check. Python passed all 181 tests.
Dart analysis had no errors/warnings and 12 existing informational findings.
The additional two download regressions pass after their correction.
After building the native DSP and deterministic audio fixture locally, all
eight previously skipped DSP/FFI tests also passed. The combined stability and
presence selection passed 17 tests on the next run.

The ten-cycle widget workload passed with no exceptions or retained timeline
listeners; host elapsed time was 9,890 ms. RSS samples in MiB were 342.3, 353.6,
356.5, 363.3, 317.0, 315.0, 295.1, 264.1, 261.5, and 262.3. This is a short
diagnostic run, not a claim of leak freedom or interactive frame performance.
The next ten-cycle run took 5,196 ms and RSS rose from 348.1 to 388.6 MiB,
mostly during the early cycles. The differing short-run trends reinforce the
need for a longer post-warmup soak rather than treating either run as proof.
Remote PR checks supply platform-specific results; this local host cannot
establish Windows/macOS application behavior.

The new CI runs native audio DSP tests, lifecycle/recovery/media/voice tests,
and the profile workload independently on Windows, Linux and macOS. Stable Chrome
also runs regressions and the release workload in both layout modes.
Browser version, logical CPU count and WebGL renderer identification accompany
the profile results; a separate context is queried after measurement and released.
Logical surface sizes, physical view dimensions and device pixel ratio are
recorded too: forcing a layout does not ensure identical pixel workloads on
different runners. Timing comparisons require equivalent hardware and display
geometry. Existing static analysis and authenticated Linux integration now run
on pull requests.
The existing Web voice suite is reusable and runs on PRs too: it builds the
actual DSP WebAssembly, checks release assets, puts recorded noisy speech
through the app's Dart/LiveKit/WebRTC sender, and exercises microphone restarts,
missing assets, worker traps/hangs and audio-context recovery. Main CI calls it
once rather than duplicating that suite inside its stability job.
Main-branch publication waits for the stability workflow, and macOS build
failures are no longer ignored by desktop builds. Web Pages deploys the exact
revision from successful main CI instead of publishing every push before its
checks finish; explicit manual deployment remains available.

The published Web application was inspected through login and appearance
settings. No JavaScript errors were observed during that limited session.
It was the baseline deployment, without an authenticated account. The browser
was background-throttled, so its animation timing was discarded. It supplies
no performance claim for this change.

## Measured CI snapshot

Revision `1484e062da723fdb79da4c348e2ef65f10d81bba` passed
[all four platform stability jobs](https://github.com/PondLabs/roosterchat/actions/runs/37099982474),
[static analysis](https://github.com/PondLabs/roosterchat/actions/runs/37099982478),
[Synapse integration and native WebRTC audio](https://github.com/PondLabs/roosterchat/actions/runs/37099982471),
and [all three production desktop builds](https://github.com/PondLabs/roosterchat/actions/runs/37100102669).
Each native stability job passed 76 audio DSP tests and 110 Flutter regressions;
Web passed 30 regressions. Each platform completed twenty timeline cycles.
The later media-disposal regression and reusable PR Web voice job are additional
checks: their latest results are recorded in the accompanying PR.

Measurements below are milliseconds per frame, with separate build/raster
measurements; they do not sum into end-to-end frame latency.

| Runner / layout | Frames | p90 build | p90 raster | p99 build | p99 raster |
| --- | ---: | ---: | ---: | ---: | ---: |
| Linux / desktop | 417 | 5.576 | 15.473 | 8.995 | 111.270 |
| Linux / mobile | 503 | 2.938 | 7.541 | 3.809 | 15.016 |
| Windows / desktop | 529 | 3.599 | 2.394 | 9.248 | 10.311 |
| Windows / mobile | 529 | 2.130 | 1.530 | 3.092 | 2.449 |
| macOS / desktop | 450 | 3.800 | 1.793 | 10.406 | 46.356 |
| macOS / mobile | 442 | 2.254 | 1.477 | 4.114 | 28.195 |
| Web / desktop | 530 | 23.900 | 55.500 | 44.699 | 82.600 |
| Web / mobile | 531 | 10.500 | 23.600 | 15.000 | 32.000 |

Chrome reported ANGLE Vulkan SwiftShader, a software renderer, with four logical
CPUs. Its desktop workload exceeded Flutter's 16 ms raster budget in 510 of 530
frames, and mobile in 496 of 531. This is a reproducible CI performance finding,
not proof of equivalent performance on a physical GPU or a 60 FPS guarantee.
Native p99 raster outliers also merit device profiling. Hardware/display
differences prevent ranking operating systems using these numbers.
Web heap samples varied with garbage collection (desktop roughly 91–149 MiB,
mobile 95–156 MiB); neither these samples nor native RSS establish leak freedom.

## Limits and recommended follow-up

Passing these checks reduces known failure modes; it does not guarantee that
daily use cannot crash. CI's native workload is a synthetic chat scene, not
hours of authenticated media playback or WebRTC traffic. Mobile layout coverage
in Chromium does not validate Safari/iOS, mobile keyboard behavior, touch input,
or device resource limits. A macOS runner does not exercise both Intel and ARM
hardware merely because release binaries are universal.

Recommended next validation is an eight-hour authenticated soak with repeated
room/account switches, media playback, active calls, screen sharing, temporary
network loss and suspend/resume. Compare post-warmup memory over repeated runs,
collect crash logs, and establish runner-specific frame/latency budgets before
making performance thresholds blocking. Include Safari/iOS and Firefox, macOS
Intel/ARM, and ordinary Windows/Linux machines with production bundles and CEF
enabled. The synthetic profile workload does not qualify that browser runtime.

Additional candidates found during review require focused reproduction:
image decoding listeners without error completion and ownership of context
timelines when overlapping requests complete.
Treat these as investigation leads, not confirmed defects or completed fixes.
