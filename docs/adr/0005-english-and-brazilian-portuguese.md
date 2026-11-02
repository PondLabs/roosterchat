# English and Brazilian Portuguese, and nothing half-translated

**Status: accepted (2026-10-09).**

Rooster inherited Commet's localization: `Intl.message` in the code, ARB files in `rooster/assets/l10n`, and more than twenty community translations. By October 2026 none of it worked for Rooster's people:

- The translations covered Commet's strings only. Everything Rooster added (voice rooms, the soundboard, the DJ booth, the updater, who's around) was English in every language, often as text written straight into the widgets, so a German or Portuguese Rooster showed two languages on one screen.
- Translations were loaded by language code alone, so `pt` (Commet's European Portuguese: "ficheiro", "utilizador") was the one shown, and `intl_pt_BR.arb`, where Rooster's own Portuguese had been going, was never used.
- Three generators ran over the ARB files (intl_utils, intl_translation's `generate_from_arb`, and Flutter's gen-l10n), and only intl_utils' output was used.

## Decision

- **Two languages ship: English, the source, and Brazilian Portuguese.** Brazilian Portuguese is `pt`, as Flutter and CLDR have it, so every Portuguese system gets it; European Portuguese would be `pt_PT`. `lib/config/languages.dart` lists them.
- **The other translations are hidden, not deleted.** They moved, unchanged, to `rooster/l10n/inactive/`, outside the build (Commet's European Portuguese as `intl_pt_PT.arb`). A language comes back with all of Rooster's strings translated, or not at all.
- **The repository stays English.** Code, comments, commits, pull requests, issues, docs and ARB descriptions. Strings are written in English first and translated in the same pull request; `unit_test/l10n/translations_test.dart` fails on a string the code has and a translation lacks, and on English left in a translation.
- **One generator.** intl_utils makes `lib/generated/` from `assets/l10n`; gen-l10n (`generate: true`, `l10n.yaml`) and `generate_from_arb` are gone. `scripts/extract_strings.dart` writes `intl_en.arb` from the code.
- **People pick the language.** Settings, App, General, Language: the system's, or one of the languages, applied without a restart. The Material widgets' own strings follow it.

How strings are written, translated and laid out, and how to add a language: [docs/localization.md](../localization.md).

## Consequences

- A German, French or Japanese system gets Rooster in English until someone brings that language back complete, where it used to get part of Commet's translation.
- Every new string costs a Portuguese translation in its pull request.
- Layouts have to hold longer text: Developer settings has pseudo-translations to find what does not.
