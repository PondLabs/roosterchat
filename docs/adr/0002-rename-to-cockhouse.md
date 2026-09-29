# Rename the app's own identity to Cockhouse

The fork is now Cockhouse. ADR 0001 kept Commet's installed-app, storage and build identities because renaming them would break upgrades and lose user data. This ADR renames them anyway, and covers each break it listed, so the only `commet` left is where the name is someone else's or shared with other clients.

This supersedes the "Compatibility identities we keep" list in ADR 0001 for the executable, the application IDs, the storage directories and the internal build names. The rest of ADR 0001 (the donation removal, badges, and the upstream services) stands.

## What is renamed

- **The repo folder and Dart package:** `commet/` became `cockhouse/`, and `package:commet/` became `package:cockhouse/`. The calendar widget package is now `cockhouse_calendar_widget`.
- **Application ID:** `chat.commet.commetapp` became `com.pondlabs.cockhouse`. This covers the Android package, the Linux GTK and desktop ID, Flatpak, D-Bus names and paths, the method channels, the macOS bundle, the MSIX identity and the Windows toast AUMID.
- **Executables:** `cockhouse` on Linux, `cockhouse.exe` on Windows, and `Cockhouse.app` on macOS. The Debian package is `cockhouse`, with `Replaces:` and `Breaks: commet` so it takes the old one's place.
- **Windows product name:** `Cockhouse`. This also moves the data directory, which is `%APPDATA%\PondLabs\Cockhouse` now.
- **Updater files:** the install directory `Programs\Cockhouse`, the staging directory `.cockhouse-update`, and the release asset names `cockhouse-<tag>-<platform>-...`.
- **Rust:** the crate and library `rust_lib_cockhouse`, and the C ABI symbols (`cockhouse_dsp_*`, `cockhouse_music_*`, `cockhouse_clip_*`). Their JavaScript and C++ callers were renamed to match.
- **Embedded browser:** the CEF hosts' internal scheme is `cockhouse://`, and the engine is `cockhouse_cef_engine`. Browser profiles live under `Cockhouse/cef/profiles` (Windows) and `cockhouse/cef/profiles` (Linux).
- **Source extensions:** the manifest file is `cockhouse-extension.json`.
- **Markers:** local changes in vendored code are marked `// COCKHOUSE`.

## What keeps the Commet name, and why

- **Matrix protocol:** event types, state keys, account-data keys and widget or LiveKit topics under `chat.commet.*`. Rooms and homeservers already hold them, and Commet clients read and write them. The same goes for the internal emoji pack IDs (`chat.commet.commetapp.internal_emoticons.*`), which are stored in account data.
- **The `chat.commet` URL scheme:** links and SSO redirects registered with it keep opening the app.
- **The web build's database name (`commet`):** IndexedDB cannot be renamed, and a new name would log every browser user out.
- **Upstream services and projects:** `push.commet.chat`, `proxy.commet.chat`, `calendar-widget.commet.chat`, the `commet-16334` Firebase project, the `commetchat/*` forks we depend on, and Commet's copyright attribution.
- **The GitHub repository `PondLabs/roscord`:** renaming it is a separate step. GitHub redirects the old URLs, including the API the updater calls.

## Bringing earlier installs across

What ADR 0001 was protecting is carried across explicitly:

- **Data.** On startup, before anything opens it, `lib/utils/legacy_data_migration.dart` moves the data directory in from where earlier builds kept it. That is `%APPDATA%\PondLabs\roscord`, then `%APPDATA%\commet.chat\commet` on Windows, and `$XDG_DATA_HOME/chat.commet.commetapp` on Linux (plus the cache and the browser profiles). It only moves into an empty directory, never over data, and it never stops startup. The Flatpak manifest grants access to the old app's `~/.var/app` directory for this.
- **Updates.** A build from before the rename only takes an update that contains its own executable name, and it starts that name afterwards. So every release also ships a `commet.exe` copy (Windows) or a `commet` link (Linux), from the CMake install step. That lets old installs update, and it keeps their pinned and Start menu shortcuts working. The new updater always asks for and starts `cockhouse`, and it still recognises an old `.roscord-update` staging nest.
- **Extensions.** `roscord-extension.json` is still read.

Not carried across:

- **macOS:** builds are sandboxed, so the old bundle ID's container is out of reach. Users there sign in again.
- **Android:** there were no Android releases, so there is nothing to migrate.
- **The old Flatpak:** it stays installed as a separate app. The new one copies its data over, and the old one can then be removed.

## Removing the bridge

The `commet` executable copy, the `.roscord-update` recognition, the Debian `Replaces:`/`Breaks:`, the Flatpak permission, the legacy manifest name and the data migration are all marked `_renameBridge` in `unit_test/repository_identity_test.dart`, or they sit next to a comment pointing here. They can all go once installs from before the rename are no longer expected to update directly. A few releases after the first Cockhouse release is a fair point for that. When they go, the data migration goes with them, and anyone still on an old build moves across by hand.
