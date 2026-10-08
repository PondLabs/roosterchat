# Updating

Rooster checks GitHub for a newer release and, on the desktop builds, can
install one over itself. The check is opt-in and the button is always there;
nothing is downloaded or replaced without being asked for.

## Where the versions come from

`ci.yml` cuts a release on every push to `main`: it runs the tests, builds
Windows and Linux (x64 and arm64) and macOS through `desktop-build.yml`,
works out the next tag, and `gh release create`s it with every archive
attached. They are named `rooster-<tag>-<platform>-<arch>-<mode>.<zip|tar.gz>`
(`x64` or `arm64`; macOS builds are `universal`) and each holds a single top
level directory of the same name, which is the bundle.

The arm64 builds are made natively on GitHub's arm64 runners (Flutter
cross-builds neither Windows nor Linux), from a git checkout of the Flutter
tag, since the Flutter SDK archives for Linux and Windows are x64 only. The
same locked CEF tuple has `windowsarm64` and `linuxarm64` archives
(`third_party/cef/cef.lock.json`), libwebrtc ships `win-arm64` and
`linux-arm64`, the Rust crates build for the host, and the Windows video
libraries come from a vendored `media_kit_libs_windows_video` that fetches
arm64 libmpv and ANGLE (see `third_party/README.md`). After each build,
`tools/check_bundle_arch.py` reads the machine field of every PE and ELF
file in the bundle and fails the job if one is for another architecture, so
a dependency that silently shipped x64 cannot reach a release.

Linux arm64 ships today. Windows arm64 does not yet: Flutter 3.41.9
publishes no Dart SDK and no engine for `windows-arm64` (the current stable,
3.47.6, does), so Flutter on an arm64 Windows takes the x64 Dart and builds
x64. `desktop-build.yml` accepts the platform and stops at that point rather
than ship an x64 build under an arm64 name; everything else for it is in
place. Until then Windows on Arm runs the x64 build under emulation, as it
always has. A first try of the desktop builds with 3.47.6 (October 2026)
got the arm64 Dart SDK on the Windows arm64 runner, but code generation
then stalled on every platform in `build_runner build` (build_runner
2.5.4 under that Dart), so the upgrade needs the generators brought up
together, as a change of its own.

`release.yml` is the older Commet pipeline and uploads different names
(`rooster-windows.zip`). Nothing runs it today.

The running version is `BuildConfig.VERSION_TAG`, baked in at build time by
`scripts/build_release.dart`. A local build has `development`, which parses
as no version at all, so a development build never reports an update.
`v0.0.0-artifact`, which the release workflow passes for builds that are not
releases, turns the whole thing off (`UpdateChecker.shouldCheckForUpdates`).

## Installers

`installers.yml` makes one installer per platform from those builds, each on
its own runner, and the release carries them beside the archives:

| Platform | File | Installs to |
|----------|------|-------------|
| Windows | `rooster-<tag>-windows-x64-setup.exe` (Inno Setup, `rooster/windows/installer/rooster.iss`; `/DArch=arm64` makes the arm64 one, once there is an arm64 build) | `%LOCALAPPDATA%\Programs\Rooster`, Start menu shortcut, uninstall entry. No admin. The x64 installer also installs on Windows on Arm, under emulation. |
| macOS | `rooster-<tag>-macos-universal.dmg` | Wherever `Rooster.app` is dragged; Applications is offered. |
| Linux | `rooster-<tag>-linux-x64-setup.sh` and `rooster-<tag>-linux-arm64-setup.sh` (`rooster/linux/installer/setup.sh` with the bundle appended) | `~/.local/opt/Rooster`, a launcher entry, an icon, `~/.local/bin/rooster`. No root. `--uninstall` removes it. The script refuses a bundle built for another CPU. |

Every one installs somewhere the user owns, so the updater below can replace
it. That is also why there is no .deb: `/usr` belongs to the package manager.
The Windows uninstaller lives in `Programs\.rooster-uninstall`, outside the
install, because an update replaces the install directory whole; uninstalling
deletes that directory rather than a list of files. Started by hand with a
tag, `installers.yml` makes the installers for an existing release and
attaches them.

## At launch

On desktop the app opens as a small window with the loading rooster
(`LoadingPage`, `WindowManagement.showLauncher`). Before anything else loads,
a build that can install over itself (below) looks for a newer release, and
when there is one the window stays small and shows it downloading, then the
app restarts into it. Otherwise, or when the check fails, it carries on and
the window grows into the app (`WindowManagement.openMainWindow`). Only
turning "check for updates" off stops this; not having answered yet does
not. The Linux and macOS runners open the window at the small size so it
does not flash at full size first; the Windows one stays hidden until the
first frame.

## Checking

| Where | What |
|-------|------|
| `lib/utils/update_checker.dart` | The startup check and the "update available" alert. Runs once per launch from the home screen, only when `preferences.checkForUpdates` is true. |
| `lib/utils/updater/update_release.dart` | A release and its assets, and picking the archive for this platform and architecture. Release builds only: a debug bundle is not an update. |
| `lib/utils/updater/self_updater.dart` | The stages the button shows, and the platform switch. |
| `lib/utils/updater/self_updater_native.dart` | Desktop: download, verify, unpack, swap. |
| `lib/ui/organisms/update_button.dart` | The button in general settings. |

The request is one unauthenticated GET to
`api.github.com/repos/PondLabs/roosterchat/releases/latest`, which is rate
limited to 60 an hour per IP. `releases/latest` leaves out prereleases by
design.

The button is always shown, whatever the preference says: that preference
only governs the check that runs by itself at startup, and somebody who
turned it off should still be able to ask.

## Installing over the running build

Only where the build was installed or unpacked from the archives above. A flatpak (`/app`),
a .deb or a distro package (`/usr`), a snap and a nix store path all belong to
something else and are refused (`isSelfInstallable`); so are Android and the
web. There, the button opens the release page, which is all the app ever did.

1. **Download** the archive for this platform and architecture (the ABI the
   build runs as, `Abi.current()`: an arm64 build takes the arm64 archive,
   an x64 build the x64 one, also when it is running under emulation on an
   arm64 Windows) to `.rooster-update/<tag>/`
   beside the install, or the temp directory when that is not writable.
   Beside it means putting it in place is a rename rather than a copy
   between filesystems. Where the install is comes from `updateTargetFor`
   (below).
2. **Verify** it against the `sha256` GitHub reports for the asset. An asset
   without one is not installed: there would be no way to know what arrived,
   and this unpacks over the app.
3. **Unpack** with the system's `tar`, falling back to the `archive` package.
   Windows has shipped bsdtar, which reads zip too, since Windows 10 1803.
   The Dart unpacker takes about three minutes over a 57 MB release where tar
   takes under a second, and it drops the executable bit, which would leave a
   build that cannot start.
4. **Swap**, when the user says to. A running program cannot replace its own
   directory on Windows, so a script is written next to the staged build and
   started detached: it waits for the process to go, moves the install aside,
   moves the new one in, starts it, and clears up all of `.rooster-update/`.
   If the new one will not go in, the old one is moved back — a failure
   leaves the build that was already working, starts it again and keeps
   `install-<stamp>.log` in `.rooster-update/`.

On Windows:

- The script is started in the temp directory. It used to inherit the app's
  working directory, which is the install when Explorer starts it, and
  Windows will not rename a directory a process is working in: no swap ever
  happened, and people ran the staged build from `.rooster-update/` instead.
- Moves are `[System.IO.Directory]::Move`, retried for 30 seconds while the
  install is busy (the CEF helpers closing, a virus scanner). `Move-Item`
  moves a directory with a busy file in it one file at a time and leaves
  half an install.

On Linux:

- The process ends as soon as its window is destroyed
  (`linux/my_application.cc`), which `WindowManagement.close` does last,
  once everything is released. The engine's teardown that used to follow
  waits for the raster thread to finish with a window already hidden: run
  on Ubuntu 24.04 with software GL (October 2026), the process stayed a
  minute after its window went and then died of a bus error in plugin
  teardown. The swap script waits a minute, so it could give up without
  swapping or starting anything, and the app did not come back.
- The script waits that minute, then ends a Rooster still there with
  SIGKILL, but only while `/proc/<pid>/exe` is the build being replaced.
  A zombie counts as gone.
- Builds up to v1.16.0 waited for ever for the running copy to answer on
  the single instance socket. With one stuck closing, no launch opened,
  the launcher entry included, until that process was killed. v1.17.0
  waits 3 seconds.
- A staged build whose executable cannot be run is refused: the Dart
  unpacker, the fallback when `tar` fails, drops the executable bit.

### Where the install is

`updateTargetFor` works it out from the running executable:

- **Its own directory**, normally.
- **The `.app`** on macOS, staged beside it and started again with `open`.
  The archive is unpacked with `ditto`, which keeps what an .app needs.
- **Run from inside `.rooster-update/`** (a swap that never happened, the
  staged build started by hand, maybe more than once, each staging the next
  inside itself): the build left beside the outermost `.rooster-update/` is
  replaced, and the whole nest is cleared with the swap.
- **Run from a zip opened in Explorer**, which unpacks it under the temp
  directory: the update goes to `%LOCALAPPDATA%\Programs\Rooster`, with a
  Start menu shortcut, since the next click on the zip would start the old
  build again. The button says so before the restart.

### Across the renames to Cockhouse and Rooster

Builds from before the renames were `cockhouse`/`cockhouse.exe` and, before
that, `commet`/`commet.exe`. They only accept an archive that holds their own
executable name, and they start that name after the swap. So each release
also carries `cockhouse.exe` and `commet.exe` copies (Windows) or `cockhouse`
and `commet` links (Linux), made by the CMake install step. An old build
updates into the new one and starts it through its own name, and its
shortcuts keep working. The new updater always asks for and starts
`rooster`. It also still recognises a `.cockhouse-update/` or
`.roscord-update/` nest left by an old build. The first start of the new
build moves the old data directory in (see
`docs/adr/0003-rename-to-rooster.md`, which also says when this bridge can
go).

The swap scripts are `windowsSwapScript` and `linuxSwapScript`, kept as
plain functions so `unit_test/updater/self_updater_test.dart` (Linux) and
`windows_swap_test.dart` (Windows, started the way the app starts it, from
inside the install) can run them for real against directories that are not
an install.

## Known gaps

- Nothing is signed, so Windows SmartScreen may have an opinion about the
  build that is started after a swap.
- An install under `Program Files` needs elevation to swap. This does not ask
  for it: the write probe fails, so the download lands in the temp directory
  and the move across filesystems is a copy.
- macOS builds are only ad-hoc signed, not notarized: the first open of a
  downloaded one needs System Settings → Privacy & Security → Open Anyway.
  An app still on the disk image or translocated (opened where it was
  downloaded) is read only and is not updated in place until it has been
  moved to Applications (`isSelfInstallable`). Updates fetched by the app
  are not quarantined, so they open without asking.
- The version Windows lists under installed apps is the one the installer
  wrote; updates do not change it.
- Every push to `main` publishes a release, so "update available" is a
  frequent thing to see.
