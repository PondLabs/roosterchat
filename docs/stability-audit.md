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
| Presence cache receiving 10,000 distinct keys | Declared capacity was not enforced | Evict oldest writes immediately; retain 50 entries and observe 9,950 removals |
| Logging 20,000 distinct messages | All messages remained in the global in-memory list | Retain at most 2,000 entries; preserve consecutive-message coalescing |
| Reopening a chat timeline 50 times | Global jump subscription retained closed timeline states; scroll controllers were not disposed | Release subscriptions and both replaced/current controllers; verify disposal after every cycle |

Presence shutdown now releases SDK subscriptions, the global idle observer,
the expiry timer and stream. The client invokes it before disposing its SDK.
Late presence lookups and timeline callbacks check whether their owner is still
alive. Cache expiry is checked on reads as well as periodic cleanup; cleanup no
longer waits 200 ms for every entry. Presence explicitly retains up to 2,000
recent users rather than inheriting the utility's small default capacity.

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
platform exposes them. Samples after each cycle report native process RSS or
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
the patched Linux test runtime. Regression tests pass after the corrections,
including the fifty timeline disposal cycles and the ten-cycle full timeline
workload. The local full-suite outcome and remote PR checks are recorded in the
PR. This host cannot establish Windows/macOS application behavior.

The new CI runs native audio DSP tests, lifecycle/recovery/media/voice tests,
and the profile workload independently on Windows, Linux and macOS. Chrome
also runs regressions and the release workload in both layout modes. Existing
static analysis and authenticated Linux integration now run on pull requests.
Main-branch publication waits for the stability workflow, and macOS build
failures are no longer ignored by desktop builds.

The published Web application was inspected through login and appearance
settings. No JavaScript errors were observed during that limited session.
It was the baseline deployment, without an authenticated account. The browser
was background-throttled, so its animation timing was discarded. It supplies
no performance claim for this change.

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
image decoding listeners without error completion, download-task timer/progress
ownership, and media-source resolution completing after player disposal.
Treat these as investigation leads, not confirmed defects or completed fixes.
