# Localization

Rooster ships in two languages: **English**, the language every string is
written in, and **Brazilian Portuguese**. The other languages that came
with Commet are kept in the repository but hidden: they do not build and
cannot be picked (see [Hidden languages](#hidden-languages)).

## Rules

1. **The repository is English.** Code, identifiers, comments, commit
   messages, pull requests, issues, docs and the descriptions in the ARB
   files are written in English. Only the translations themselves
   (`rooster/assets/l10n/intl_<language>.arb`) hold another language.
2. **One language per screen.** Rooster never shows English and Portuguese
   side by side. Every string a person can read goes through `Intl.message`
   and has a translation, including error messages, tooltips, notifications,
   tray and taskbar menus, the loading window and the developer tools. An
   English word stays in a translation only where the
   [glossary](#glossary) keeps it, because it is the word people actually
   use (DJ, GIF, link, soundboard).
3. **English first.** A new feature is written in English in the code, then
   translated into Portuguese in the same pull request. A string with no
   translation fails `unit_test/l10n/translations_test.dart`, so the
   Portuguese app never falls back to English.
4. **Ready for more languages.** Nothing in the code assumes English: no
   sentences glued from pieces, no plurals made with `"s"`, no word order
   baked into string concatenation, dates and numbers formatted with `intl`.
   Adding a language is a new ARB file and one line (see
   [Adding a language](#adding-a-language)).
5. **Every language fits.** Translated text is longer than English: about
   a quarter longer in Portuguese, a third or more in German. Layouts give
   text room to grow and never cut it off (see [Layout](#layout)).

## How a string is written

Every user-facing string is an `Intl.message` in a getter or method next
to the widget that shows it. `name` is the getter's own name (intl requires
it), `desc` tells a translator where the string appears, and `args` lists
the method's parameters in order:

```dart
static String get labelDjQueueEmpty => Intl.message("Nothing queued yet",
    name: "labelDjQueueEmpty",
    desc: "Shown in the DJ booth's queue while no song is queued");

static String labelDjNowPlaying(String title) => Intl.message(
    "Now playing: $title",
    name: "labelDjNowPlaying",
    args: [title],
    desc: "Over the DJ booth's controls, with the title of the song");

static String labelSoundCount(int howMany) => Intl.plural(howMany,
    one: "1 sound",
    other: "$howMany sounds",
    name: "labelSoundCount",
    args: [howMany],
    desc: "How many sounds a space's soundboard has");
```

- **Prefixes.** `label` for text that describes (titles, headers,
  descriptions), `prompt` for what a person acts on (buttons, menu entries),
  `tooltip` for tooltips, `message` for sentences the app says (errors,
  notices, timeline events), `error` for failures.
- **Whole sentences.** Pass names, numbers and other values as arguments
  and let the translation place them. Never build a sentence from
  translated pieces: `"$user " + labelJoined` cannot be translated into a
  language with a different word order.
- **Plurals** go through `Intl.plural`, never `count == 1 ? "" : "s"`.
- **Generic words** (Cancel, Save, Close, Try again, Delete…) are in
  `rooster/lib/utils/common_strings.dart`. Use them instead of adding
  another "Cancel".
- **Not in `const`.** A translated string is read at runtime, so a widget
  that shows one cannot be `const`, and a default parameter value cannot be
  one (make the parameter nullable and fall back in the body).
- **Brand names are arguments or literals inside the message**:
  Rooster (`BuildConfig.app`), Matrix, KLIPY, GitHub, Discord.
- **Numbers, dates and durations** come from `intl` in the app's language:
  `NumberFormat` (Portuguese writes "1,5 MB"), `DateFormat` skeletons such
  as `DateFormat.yMMMd()` rather than fixed patterns, and durations as
  plural messages ("3h 26min").

What stays English, untranslated: log lines (`Log.i` and friends), text
written into bug reports, exception messages nobody sees in the interface,
protocol values (event types, keys, MIME types), and the people's own
content (names, messages, room topics).

`unit_test/l10n/translations_test.dart` looks for text written straight
into the interface: the text of a `Text`, or a `tooltip:`, `label:`,
`title:`, `hintText:` and the like. A literal there that has to stay as it
is (a unit, a protocol value, a field name) gets a comment saying why, on
its line or right above it:

```dart
// Not translated: the names of a process's output streams.
header: "stdout",
```

## Workflow

From `rooster/`:

1. Write the string in English with `Intl.message`, as above.
2. `dart run scripts/extract_strings.dart` reads every `Intl.message` in the
   app (and in the calendar widget, `widgets/calendar`) into
   `assets/l10n/intl_en.arb`, puts the other ARB files in the same order,
   drops strings the code no longer has, and lists what is missing from
   each translation.
3. Add the Portuguese to `assets/l10n/intl_pt.arb`, with the same key and
   the same `{placeholders}`. Plurals keep the ICU form:
   `{howMany,plural, =1{1 som}other{{howMany} sons}}`.
4. `dart run scripts/codegen.dart` (or only `dart run intl_utils:generate`)
   regenerates `lib/generated/`.
5. `flutter test unit_test/l10n` checks that the English file matches the
   code, that every translation is complete and well formed, that no
   English is left in one, and that no text is written straight into a
   widget.

Generated code is not committed; `lib/generated/intl/messages_*.dart` and
`lib/generated/l10n.dart` come from intl_utils (the `flutter_intl` section
of `pubspec.yaml`).

## Picking the language

`rooster/lib/config/languages.dart` lists the languages that ship
(`Languages.supported`). Settings, App, General, Language has "Same as the
system" and each of them, under its own name. With "Same as the system",
Rooster takes the first of the system's (or the browser's) preferred
languages it has, so a German system with Portuguese second gets
Portuguese, and anything else gets English. Changing it applies at once,
without a restart.

The Material and Cupertino widgets' own strings (text selection, date
pickers, back buttons) follow the same language through
`GlobalMaterialLocalizations`.

## Layout

Design every widget for text a third longer than the English, and for a
second line:

- Text in a `Row` sits in `Flexible` or `Expanded`, never in a fixed width.
- A label that must stay on one line gets `maxLines: 1` with
  `overflow: TextOverflow.ellipsis`, and its full text in a tooltip when it
  can be cut.
- Buttons size themselves to their label; a row of buttons wraps (`Wrap`,
  or `OverflowBar` in dialogs) instead of overflowing.
- Badges and pills (LIVE, counts) have a minimum width, not a fixed one.
- Settings tiles put the description under the title and let both wrap.

Developer settings, Rendering, **Pseudo-translations** shows every string
accented and stretched the way a long language would, short strings the
most (from 30% to 80% longer), between brackets: "Settings" becomes
`[Šéťťíñğš ~~~~~~~]`. Anything cut off (a missing `]`), overflowing, or
still plain English with it on needs fixing. **Show translation keys**
shows each string's key instead of its text. Both apply at once.

## Outside the app's strings

A few things are translated where they live, not in the ARB files:

| Where | What |
|---|---|
| `rooster/web/index.html` | The splash captions, before the app has loaded (the loading window's lines) |
| `rooster/web/auth.html` | The page single sign-on comes back to on the web |
| `rooster/linux/*/com.pondlabs.rooster.desktop` | The launcher's tooltip and its call actions (`Name[pt]`, `Comment[pt]`) |
| `rooster/windows/installer/rooster.iss` | The installer, from Inno Setup's own translations (`[Languages]`) |
| `rooster/ios/Runner/Info.plist`, `rooster/macos/Runner/Info.plist` | The languages the app declares (`CFBundleLocalizations`) |

The web pages pick their language the way the app does: the one picked in
settings (`flutter.app_language` in localStorage), else the browser's.

Still English: the macOS app menu (`macos/Runner/Base.lproj/MainMenu.xib`,
which would need a `pt-BR.lproj` strings file), and the store and package
descriptions (`web/manifest.json`, the Flatpak metainfo, the Debian
control files).

## Adding a language

1. Copy `rooster/assets/l10n/intl_pt.arb` to `intl_<code>.arb` (or move a
   hidden one back from `rooster/l10n/inactive/`) and translate every
   string. The code is the language's (`de`, `fr`), with a region or script
   only when it differs from the default (`pt_PT`, `zh_Hant`).
2. Add it to `Languages.supported` with its name in itself.
3. Add it to the places in [Outside the app's strings](#outside-the-apps-strings).
4. Write its section in the style guide below, with a glossary.
5. Run the workflow above. The tests list every string still missing.
6. Look at the app with it, and with pseudo-translations, for anything cut
   off.

## Hidden languages

Commet's community translated it into more than twenty languages. Those
translations cover Commet's strings, not Rooster's, so shipping them would
show half of Rooster in English. They are kept, unchanged, in
`rooster/l10n/inactive/`, outside the build, for whoever brings one back.
The European Portuguese translation (`intl_pt.arb` in Commet) was replaced
by the Brazilian one: Brazilian Portuguese is `pt`, as in Flutter and CLDR,
and European Portuguese would be `pt_PT`.

## Brazilian Portuguese style

- **Talk like the English does**: plain, warm and direct, to a friend. Use
  "você", never "tu" or "o usuário". Humour only where the English has it,
  and adapted, not translated word for word ("Waking up the flock…" is
  "Acordando o galinheiro…").
- **Sentence case.** Only the first word and names are capitalised, even
  where the English uses Title Case: "Reply In Thread" is "Responder no
  tópico".
- **Brazilian, not European**: arquivo (not ficheiro), usuário (not
  utilizador), tela (not ecrã), celular, configurações, baixar, excluir,
  "está digitando" (not "está a digitar").
- **Buttons are infinitives**: Salvar, Excluir, Entrar na chamada. The
  usual ones: Join → Entrar, Next → Avançar, Done → Concluir, Try again →
  Tentar novamente, Decline and Reject → Recusar, Play (a sound or a song)
  → Tocar. "Are you sure you want to…" is "Tem certeza de que quer…".
- **Adjectives agree with their noun.** "Public", "Enabled" and the like
  are masculine or feminine in Portuguese, so a shared label only fits the
  nouns it was written for. In the code, give each noun its own message
  rather than reusing one adjective.
- **Short where space is short.** Tooltips, buttons and badges should not
  grow much past the English; pick the shorter word when both are right.
- **Typography**: the ellipsis character (…), not three dots, and quotes as
  “…” only where the English has them.

### Glossary

| English | Português | Notes |
|---|---|---|
| room | sala | |
| space | espaço | |
| channel / text channel / voice channel | canal / canal de texto / canal de voz | |
| category (of channels) | categoria | |
| call / join call / leave call | chamada / entrar na chamada / sair da chamada | "call" only in casual copy ("Vem pra call") |
| hang up / disconnect | desligar / desconectar | |
| mute / unmute (microphone) | silenciar / dessilenciar | |
| deafen / undeafen | desativar áudio / reativar áudio | |
| screen share / share your screen | compartilhamento de tela / compartilhar sua tela | |
| stream (a screen share or camera being watched) | transmissão | |
| watch stream / stop watching | assistir / parar de assistir | |
| LIVE | AO VIVO | |
| soundboard | soundboard | kept in English, as Brazilian Discord users say it |
| sound (on the soundboard) / entrance sound | som / som de entrada | |
| DJ booth / the decks / DJ | cabine de DJ / a cabine / DJ | |
| queue / song / track | fila / música / faixa | |
| source extension | extensão de fonte | where songs and sounds come from |
| noise suppression | supressão de ruído | |
| input sensitivity | sensibilidade de entrada | |
| microphone / speakers / headphones | microfone / alto-falantes / fones de ouvido | |
| input / output device | dispositivo de entrada / saída | |
| homeserver | servidor | "servidor Matrix" when it could be confused |
| end-to-end encryption / encrypted | criptografia de ponta a ponta / criptografado | |
| verify / session / device | verificar / sessão / dispositivo | |
| recovery key / security phrase | chave de recuperação / frase de segurança | |
| backup (of keys or messages) | backup | what WhatsApp, Google and Apple call it in Brazil |
| cross-signing | assinatura cruzada | |
| emoji / emote / custom emoji | emoji / emote / emoji personalizado | |
| sticker / sticker pack | figurinha / pacote de figurinhas | |
| GIF | GIF | |
| reaction / react | reação / reagir | |
| thread | tópico | |
| room topic | descrição | "tópico" is a thread |
| reply / mention / pin | responder / mencionar / fixar | |
| invite / ban / kick | convidar / banir / expulsar | |
| role / admin / moderator / owner | cargo / administrador / moderador / dono | |
| permission / power level | permissão / nível de permissão | |
| notification / keyword | notificação / palavra-chave | |
| preview (of a link or media) | prévia | |
| state events | eventos de estado | |
| who's around / pull up a chair | quem está por aí / puxe uma cadeira | |
| away / idle / online / offline | ausente / inativo / online / offline | |
| status | status | |
| Home (the screen) | Início | |
| direct message | mensagem direta | |
| favorites | favoritos | |
| search | buscar / busca | |
| unread | não lida | |
| delete / remove | excluir / remover | "deletar" is never used |
| upload / attachment | enviar / anexo | |
| link / URL | link | "URL" only in technical settings |
| shortcut | atalho | |
| tray / taskbar / Dock | bandeja do sistema / barra de tarefas / Dock | |
| update / release / install / restart | atualização / versão / instalar / reiniciar | |
| desktop app | aplicativo para computador | |
| widget (a web app in a room) | widget | |
| settings / appearance / theme | configurações / aparência / tema | |
| developer mode | modo de desenvolvedor | |
| logs | logs | |
| chat | chat | |
| badge | insígnia | |
| bitrate / frame rate | taxa de bits / taxa de quadros | |
| account / sign in / sign out | conta / entrar / sair | |
| password / username / display name | senha / nome de usuário / nome de exibição | |
| profile / avatar / banner | perfil / avatar / banner | |
| crew, flock (brand) | galera, turma; galinheiro | as the English: only in friendly moments |
