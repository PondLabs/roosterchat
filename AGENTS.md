# AGENTS.md

Rules for every coding agent working in this repository (Claude Code,
Codex and the like) and for the people reviewing their work. `CLAUDE.md`
maps the code; `docs/localization.md` has the details behind the rules
below.

## Localization

Rooster ships in every language listed in `Languages.supported`
(`rooster/lib/config/languages.dart`). Today that is English, the source,
and Brazilian Portuguese; more languages are coming. From now on,
everything that is built is localized into **all** of them, the way the
first localization was done (`docs/adr/0005-english-and-brazilian-portuguese.md`).

1. **The repository is English.** Commits, code comments, pull requests,
   issues, docs, identifiers and the descriptions in the ARB files are
   written in English, whatever language the conversation is in. Only the
   translation files (`rooster/assets/l10n/intl_<code>.arb`) hold another
   language.
2. **Never mix languages.** A screen is entirely in one language. Every
   string a person can read (labels, buttons, tooltips, dialogs, errors,
   notifications, menus outside the window, the developer tools) is an
   `Intl.message` with a translation in every language that ships. A
   translation keeps an English word only where it makes sense, or where
   the English term is far better known than the local one (DJ, GIF,
   link, soundboard): see the glossary in `docs/localization.md`, and
   think of the languages to come before adding to it.
3. **English first, then every language.** A feature is written in
   English, then its strings are translated into every language that
   ships, in the same change. No string waits for later:
   `flutter test unit_test/l10n` fails on any string a language lacks, on
   English left in a translation, and on text written straight into a
   widget.
4. **Ready for more languages.** Values go in placeholders, never into
   sentences glued from pieces; plurals go through `Intl.plural`, never
   `count == 1 ? "" : "s"`; numbers and dates come from `intl` in the
   app's language. Adding a language is an ARB file, one line in
   `Languages.supported` and the places listed in `docs/localization.md`
   ("Outside the app's strings", "Adding a language"), so nothing in the
   code may assume English or only two languages.
5. **Every language fits.** Whatever the language, nothing is cut off,
   overflows or falls out of line with the design. Layouts hold text a
   third longer than the English and a second line: text in a `Row` sits
   in `Flexible` or `Expanded`; a label that has to stay on one line gets
   an ellipsis and its full text in a tooltip; rows of buttons wrap
   (`Wrap`, `OverflowBar`); no fixed width around text. Look at new UI
   with Developer settings, Rendering, Pseudo-translations, and in widget
   tests.

### Every change that adds or changes a string

From `rooster/`:

1. Write it in English as an `Intl.message` (`docs/localization.md`, "How
   a string is written"). A literal that has to stay as it is (a unit, a
   protocol value) gets a `// Not translated: <why>` comment instead.
2. `dart run scripts/extract_strings.dart` updates `assets/l10n/intl_en.arb`
   and lists what every other language is missing.
3. Translate each new string into every `assets/l10n/intl_<code>.arb`, with
   the same `{placeholders}` and plural shape, following that language's
   style guide and glossary in `docs/localization.md`.
4. `dart run intl_utils:generate`, then `flutter test unit_test/l10n`.
