# Rename the app to Rooster

Cockhouse is now Rooster. Every identity ADR 0002 gave the app's own name is renamed again, the same way: `cockhouse` became `rooster`, `Cockhouse` became `Rooster`, and `COCKHOUSE` became `ROOSTER`. That covers the `rooster/` folder and `package:rooster/`, the application ID `com.pondlabs.rooster`, the `rooster` executable (`rooster.exe`, `Rooster.app`), the Debian package, the Windows data directory `%APPDATA%\PondLabs\Rooster`, the updater's `Programs\Rooster` and `.rooster-update`, the release assets `rooster-<tag>-<platform>-...`, the Rust library `rust_lib_rooster` and its `rooster_*` C symbols, the CEF `rooster://` scheme and `rooster_cef_engine`, the extension manifest `rooster-extension.json`, and the `// ROOSTER` markers in vendored code.

What ADR 0002 kept under Commet's name stays as it is, for the same reasons: the `chat.commet.*` Matrix identifiers, the `chat.commet` URL scheme, the web build's `commet` database, Commet's services and attribution.

The GitHub repository was renamed too, from `PondLabs/roscord` to `PondLabs/roosterchat`. GitHub redirects the old URLs, including the releases API that builds from before call to check for updates, so those keep updating. Don't create a new repository named `PondLabs/roscord`: it would take over the old URLs and break the redirect.

ADR 0002 stays as the record of the first rename, so it still says Cockhouse.

## Bringing Cockhouse installs across

Cockhouse shipped (v0.26.0 and v0.27.0), so its installs get the same bridge ADR 0002 built for Commet's, with Cockhouse added in front:

- **Data.** `lib/utils/legacy_data_migration.dart` looks for `%APPDATA%\PondLabs\Cockhouse` (and the cache and browser profiles beside it) on Windows, and `com.pondlabs.cockhouse` on Linux, before the older Commet and roscord locations. The Flatpak manifest also grants access to `~/.var/app/com.pondlabs.cockhouse`.
- **Updates.** Every release ships a `cockhouse.exe` copy (Windows) or a `cockhouse` link (Linux) beside the `commet` one, so Cockhouse builds take the update and start it, and their shortcuts keep working. The updater still recognises a `.cockhouse-update` staging nest. Cockhouse builds find the new assets because they match on the `-<platform>-x64-release` suffix, not the name.
- **Packages and extensions.** The Debian package `Replaces:` and `Breaks:` both `cockhouse` and `commet`, and `cockhouse-extension.json` is still read.

Not carried across: macOS Cockhouse installs, whose sandbox container belongs to the old bundle ID (they sign in again), and the old Cockhouse Flatpak, which stays installed until it is removed.

## Removing the bridge

As in ADR 0002, everything above is marked `_renameBridge` in `unit_test/repository_identity_test.dart` or sits next to a comment pointing here. That test now also fails on any `cockhouse` it finds outside the allowlist on the identity surfaces it inspects. The Cockhouse and Commet bridges can go together, a few releases after the first Rooster release.
