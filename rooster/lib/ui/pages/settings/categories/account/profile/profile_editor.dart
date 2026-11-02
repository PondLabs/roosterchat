import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/user_color/user_color_component.dart';
import 'package:rooster/client/components/user_presence/user_idle_watcher.dart';
import 'package:rooster/client/components/user_presence/user_presence_component.dart';
import 'package:rooster/client/matrix/matrix_member.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/code_block.dart';
import 'package:rooster/ui/molecules/settings_entry_bool.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/user_profile/profile_card_theme.dart';
import 'package:rooster/ui/pages/settings/categories/account/profile/name_color_palette.dart';
import 'package:rooster/ui/pages/settings/categories/account/profile/name_color_picker.dart';
import 'package:rooster/ui/pages/settings/categories/account/profile/profile_preview.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:rooster/utils/picker_utils.dart';
import 'package:rooster/utils/scaled_app.dart';
import 'package:rooster/utils/timezone_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Everything about our profile that other people see, for one account.
/// Edits go into a draft that the preview shows straight away; nothing is
/// sent until Save.
class ProfileEditor extends StatefulWidget {
  const ProfileEditor({required this.client, super.key});
  final Client client;

  /// The key of the Save button, for tests.
  static const saveKey = ValueKey("profile-settings-save");
  static const nameFieldKey = ValueKey("profile-settings-name");

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

/// The profile as it is on the server, or as we would like it to be.
class _Draft {
  ImageProvider? picture;
  ImageProvider? banner;
  String name = "";
  String pronouns = "";
  String status = "";
  String bio = "";
  String? timezone;
  NameColor? nameColor;
  Color? cardColor;
  Brightness? cardBrightness;
  Set<ProfileBadge> badges = const {};

  _Draft copy() => _Draft()
    ..picture = picture
    ..banner = banner
    ..name = name
    ..pronouns = pronouns
    ..status = status
    ..bio = bio
    ..timezone = timezone
    ..nameColor = nameColor
    ..cardColor = cardColor
    ..cardBrightness = cardBrightness
    ..badges = badges;
}

/// One thing Save writes: what it compares, how it moves between drafts, and
/// how it reaches the server.
typedef _Part = ({
  Object? Function(_Draft d) value,
  void Function(_Draft from, _Draft to) copy,
  Future<void> Function(_Draft d) write,
});

bool _same(Object? a, Object? b) =>
    a is Set && b is Set ? setEquals(a, b) : a == b;

class _ProfileEditorState extends State<ProfileEditor> {
  late final UserProfileComponent component =
      widget.client.getComponent<UserProfileComponent>()!;
  UserColorComponent? get colors =>
      widget.client.getComponent<UserColorComponent>();
  String get selfId => widget.client.self!.identifier;

  Profile? profile;
  _Draft saved = _Draft();
  _Draft draft = _Draft();
  List<ProfileBadge> availableBadges = const [];
  String? deviceTimezone;
  Color? colorOverride;
  bool loaded = false;
  bool saving = false;
  bool saveFailed = false;

  ColorScheme? cardScheme;
  Object? cardSchemeInputs;

  final nameController = TextEditingController();
  final pronounsController = TextEditingController();
  final statusController = TextEditingController();
  final bioController = TextEditingController();

  String get labelProfileSettingsIntro => Intl.message(
      "This is how people see you. Try things out and watch the preview: "
      "nobody sees a change until you save.",
      name: "labelProfileSettingsIntro",
      desc: "Settings > Profile: the line at the top of the page");

  String get labelProfileSettingsPictureAndBanner =>
      Intl.message("Picture and banner",
          name: "labelProfileSettingsPictureAndBanner",
          desc: "Settings > Profile: heading of the section with the user's "
              "profile picture and banner image");

  String get labelProfileSettingsPicture => Intl.message("Your picture",
      name: "labelProfileSettingsPicture",
      desc: "Settings > Profile: title of the user's profile picture (avatar)");

  String get labelProfileSettingsPictureDescription =>
      Intl.message("Everyone sees it, in every Matrix app.",
          name: "labelProfileSettingsPictureDescription",
          desc: "Settings > Profile: who sees the user's profile picture");

  String get labelProfileSettingsBanner => Intl.message("Your banner",
      name: "labelProfileSettingsBanner",
      desc: "Settings > Profile: title of the wide image across the top of "
          "the user's profile card");

  String get labelProfileSettingsBannerDescription => Intl.message(
      "It goes across the top of your card. People on Rooster see it; most "
      "other apps don't show banners.",
      name: "labelProfileSettingsBannerDescription",
      desc: "Settings > Profile: where the banner shows and who sees it");

  String get labelProfileSettingsNoBanner =>
      Intl.message("Without a banner, your card shows a blur of your picture.",
          name: "labelProfileSettingsNoBanner",
          desc: "Settings > Profile: inside the empty banner box when the "
              "user has no banner but has a profile picture");

  String get promptProfileSettingsChangeImage => Intl.message("Change",
      name: "promptProfileSettingsChangeImage",
      desc: "Settings > Profile: button that picks a new image for the "
          "profile picture or the banner");

  String get labelProfileSettingsName => Intl.message("Name",
      name: "labelProfileSettingsName",
      desc: "Settings > Profile: heading of the section with the display "
          "name and pronouns");

  String get labelProfileSettingsDisplayName => Intl.message("Display name",
      name: "labelProfileSettingsDisplayName",
      desc: "Settings > Profile: label of the display name field");

  String labelProfileSettingsDisplayNameDescription(String username) =>
      Intl.message(
          "Everyone sees it, in every room. Your username, $username, never "
          "changes.",
          name: "labelProfileSettingsDisplayNameDescription",
          args: [username],
          desc: "Settings > Profile: under the display name field. The "
              "username is the Matrix ID, such as @alice:matrix.org");

  String get errorProfileSettingsDisplayNameEmpty =>
      Intl.message("Your name can't be empty.",
          name: "errorProfileSettingsDisplayNameEmpty",
          desc: "Settings > Profile: under the display name field when it "
              "was emptied; saving is off until there is a name");

  String get labelProfileSettingsPronouns => Intl.message("Pronouns",
      name: "labelProfileSettingsPronouns",
      desc: "Settings > Profile: label of the pronouns field");

  String get labelProfileSettingsPronounsHint => Intl.message("they/them",
      name: "labelProfileSettingsPronounsHint",
      desc: "Settings > Profile: example in the empty pronouns field. Use "
          "pronouns in the target language");

  String get labelProfileSettingsPronounsDescription => Intl.message(
      "Shown under your name on your card. People on Rooster see them, and "
      "so do some other apps.",
      name: "labelProfileSettingsPronounsDescription",
      desc: "Settings > Profile: under the pronouns field, where they show "
          "and who sees them");

  String get labelProfileSettingsAboutYou => Intl.message("About you",
      name: "labelProfileSettingsAboutYou",
      desc: "Settings > Profile: heading of the section with the status "
          "message, the about me text and the local time");

  String get labelProfileSettingsStatus => Intl.message("Status message",
      name: "labelProfileSettingsStatus",
      desc: "Settings > Profile: label of the field for a short status line");

  String get labelProfileSettingsStatusDescription => Intl.message(
      "A short line next to your picture on your card: people on Rooster "
      "see it, and other apps may too, depending on your server. Online, "
      "Away and Invisible are set from the dot on your picture at the bottom "
      "of the sidebar.",
      name: "labelProfileSettingsStatusDescription",
      desc: "Settings > Profile: under the status message field, what it is "
          "and who sees it. 'Your server' is the user's Matrix homeserver. "
          "Online, Away and Invisible are the options of the menu opened "
          "from the presence dot on the user's own picture at the bottom of "
          "the sidebar: use that menu's words");

  String get labelProfileSettingsAboutMe => Intl.message("About me",
      name: "labelProfileSettingsAboutMe",
      desc: "Settings > Profile: label of the field where the user writes "
          "about themselves (their bio)");

  String get labelProfileSettingsAboutMeDescription => Intl.message(
      "Shown on your card. People on Rooster see it, and so do some other "
      "apps. Markdown works.",
      name: "labelProfileSettingsAboutMeDescription",
      desc: "Settings > Profile: under the about me field, where it shows "
          "and who sees it");

  String get labelProfileSettingsShowLocalTime =>
      Intl.message("Show my local time",
          name: "labelProfileSettingsShowLocalTime",
          desc: "Settings > Profile: switch that puts the user's time zone "
              "on their card");

  String labelProfileSettingsShowLocalTimeDescription(String timezone) =>
      Intl.message("People see what time it is where you are ($timezone).",
          name: "labelProfileSettingsShowLocalTimeDescription",
          args: [timezone],
          desc: "Settings > Profile: under the local time switch, with the "
              "time zone, such as America/Sao_Paulo");

  String labelProfileSettingsTimezoneDiffers(String card, String device) =>
      Intl.message("Your card says $card, but this device is in $device.",
          name: "labelProfileSettingsTimezoneDiffers",
          args: [card, device],
          desc: "Settings > Profile: when the time zone on the user's card is "
              "not this device's. Both are time zones, such as "
              "America/Sao_Paulo");

  String get promptProfileSettingsUseDeviceTimezone =>
      Intl.message("Use this device's time zone",
          name: "promptProfileSettingsUseDeviceTimezone",
          desc: "Settings > Profile: button that puts this device's time zone "
              "on the user's card");

  String get labelProfileSettingsColors => Intl.message("Colors",
      name: "labelProfileSettingsColors",
      desc: "Settings > Profile: heading of the section with the name color "
          "and the card colors");

  String get labelProfileSettingsNameColor => Intl.message("Name color",
      name: "labelProfileSettingsNameColor",
      desc: "Settings > Profile: title of the color picker for the user's "
          "name in chats");

  String get labelProfileSettingsNameColorDescription => Intl.message(
      "Your name in chats and member lists. It's the same in every space and "
      "chat. People on Rooster, and in other apps that support name colors, "
      "see it. Other apps pick a color from your username.",
      name: "labelProfileSettingsNameColorDescription",
      desc: "Settings > Profile: what the name color changes, that it is one "
          "color for all of the user's spaces and chats, and who sees it");

  String get labelProfileSettingsColorOverrideNote => Intl.message(
      "You gave your own name a color earlier that only you see, so your "
      "devices show that color instead. Other people don't see it.",
      name: "labelProfileSettingsColorOverrideNote",
      desc: "Settings > Profile: under the name color, when the user once "
          "recolored their own name with the old only-you color, next to a "
          "button that removes it");

  String get labelProfileSettingsCardColors => Intl.message("Card colors",
      name: "labelProfileSettingsCardColors",
      desc: "Settings > Profile: title of the color picker for the user's "
          "profile card");

  String get labelProfileSettingsCardColorsDescription => Intl.message(
      "The colors of your card. People on Rooster see them; most other apps "
      "don't show them. Automatic takes them from your banner or picture and "
      "follows each person's theme.",
      name: "labelProfileSettingsCardColorsDescription",
      desc: "Settings > Profile: what the card colors change and who sees "
          "them. 'Automatic' is the first choice of the picker");

  String get labelProfileSettingsCardMatchTheme =>
      Intl.message("Match each person's theme",
          name: "labelProfileSettingsCardMatchTheme",
          desc: "Settings > Profile: card style choice, the card is light or "
              "dark like the theme of whoever looks at it");

  String get labelProfileSettingsCardAlwaysDark => Intl.message("Always dark",
      name: "labelProfileSettingsCardAlwaysDark",
      desc: "Settings > Profile: card style choice, the card is dark for "
          "everyone");

  String get labelProfileSettingsCardAlwaysLight => Intl.message("Always light",
      name: "labelProfileSettingsCardAlwaysLight",
      desc: "Settings > Profile: card style choice, the card is light for "
          "everyone");

  String get labelProfileSettingsBadges => Intl.message("Badges",
      name: "labelProfileSettingsBadges",
      desc: "Settings > Profile: heading of the section where the user picks "
          "which badges show on their card");

  String get labelProfileSettingsBadgesDescription => Intl.message(
      "Pick the badges your card shows. People on Rooster see them; most "
      "other apps don't show badges.",
      name: "labelProfileSettingsBadgesDescription",
      desc: "Settings > Profile: over the list of the user's badges, what "
          "they are and who sees them");

  String get promptProfileSettingsViewRawProfile =>
      Intl.message("View raw profile",
          name: "promptProfileSettingsViewRawProfile",
          desc: "Settings > Profile, developer mode: button that shows the "
              "profile's JSON, and the title of the dialog it opens");

  String get labelProfileSettingsUnsavedChanges =>
      Intl.message("You have unsaved changes.",
          name: "labelProfileSettingsUnsavedChanges",
          desc: "Settings > Profile: in the bar at the bottom when the user "
              "changed something and has not saved it");

  String get promptProfileSettingsSaveChanges => Intl.message("Save changes",
      name: "promptProfileSettingsSaveChanges",
      desc: "Settings > Profile: button that sends the changes to the server");

  String get errorProfileSettingsSaveFailed => Intl.message(
      "Some changes could not be saved. They are still here, so you can try "
      "again.",
      name: "errorProfileSettingsSaveFailed",
      desc: "Settings > Profile: under the save bar when part of a save "
          "failed");

  late final List<_Part> parts = [
    (
      value: (d) => d.picture,
      copy: (from, to) => to.picture = from.picture,
      write: (d) => switch (d.picture) {
            MemoryImage image => widget.client.setAvatar(image.bytes, ""),
            _ => widget.client.removeAvatar(),
          },
    ),
    (
      value: (d) => d.banner,
      copy: (from, to) => to.banner = from.banner,
      write: (d) => switch (d.banner) {
            MemoryImage image => component.setBanner(image.bytes),
            _ => component.removeBanner(),
          },
    ),
    (
      value: (d) => d.name.trim(),
      copy: (from, to) => to.name = from.name,
      write: (d) => widget.client.setDisplayName(d.name.trim()),
    ),
    (
      value: (d) => d.pronouns.trim(),
      copy: (from, to) => to.pronouns = from.pronouns,
      write: (d) => component.setPronouns(d.pronouns.trim()),
    ),
    (
      value: (d) => d.status.trim(),
      copy: (from, to) => to.status = from.status,
      write: writeStatus,
    ),
    (
      value: (d) => d.bio.trim(),
      copy: (from, to) => to.bio = from.bio,
      write: (d) => d.bio.trim().isEmpty
          ? component.removeBio()
          : component.setBio(d.bio.trim()),
    ),
    (
      value: (d) => d.timezone,
      copy: (from, to) => to.timezone = from.timezone,
      write: (d) => d.timezone == null
          ? component.removeTimezone()
          : component.setTimezone(d.timezone!),
    ),
    (
      value: (d) => d.nameColor,
      copy: (from, to) => to.nameColor = from.nameColor,
      write: (d) => colors!.setOwnPublicColor(d.nameColor),
    ),
    (
      value: (d) => (d.cardColor, d.cardBrightness),
      copy: (from, to) => to
        ..cardColor = from.cardColor
        ..cardBrightness = from.cardBrightness,
      write: (d) => d.cardColor == null
          ? component.removeProfileColorScheme()
          : component.setProfileColorScheme(d.cardColor!, d.cardBrightness),
    ),
    (
      value: (d) => d.badges,
      copy: (from, to) => to.badges = from.badges,
      write: (d) => component.setProfileBadges(d.badges.toList()),
    ),
  ];

  bool changed(_Part part) => !_same(part.value(draft), part.value(saved));

  bool get dirty => parts.any(changed);

  bool get nameMissing => draft.name.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loaded) refreshCardScheme();
  }

  @override
  void dispose() {
    nameController.dispose();
    pronounsController.dispose();
    statusController.dispose();
    bioController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final profile = await component.getProfile(selfId);
    final base = _Draft()
      ..picture = profile.avatar
      ..banner = profile.banner
      ..name = profile.displayName;
    if (profile case ProfileWithPronouns p)
      base.pronouns = p.pronouns.join(", ");
    if (profile case ProfileWithPresence p) {
      base.status = p.precence?.message?.message ?? "";
    }
    if (profile case ProfileWithBio p) base.bio = p.plaintextBio ?? "";
    if (profile case ProfileWithTimezone p) base.timezone = p.timezone;
    if (profile case ProfileWithColorScheme p) {
      base
        ..cardColor = p.color
        ..cardBrightness = p.brightness;
    }
    if (profile case ProfileWithBadges p) {
      base.badges = (await p.getBadges()).toSet();
    }
    final available = await component.getAvailableBadges();

    try {
      base.nameColor = await colors?.getOwnPublicColor();
    } catch (e, s) {
      Log.onError(e, s, content: "Could not read our name color");
    }

    String? device;
    try {
      device = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (e) {
      Log.w("Could not read this device's time zone: $e");
    }
    await TimezoneUtils.instance.init();

    if (!mounted) return;
    setState(() {
      this.profile = profile;
      saved = base;
      draft = base.copy();
      availableBadges = available;
      deviceTimezone = device;
      colorOverride = colors?.getOverride(selfId);
      fillControllers();
      loaded = true;
    });
    refreshCardScheme();
  }

  void fillControllers() {
    nameController.text = draft.name;
    pronounsController.text = draft.pronouns;
    statusController.text = draft.status;
    bioController.text = draft.bio;
  }

  void edit(VoidCallback change) {
    setState(change);
    refreshCardScheme();
  }

  /// The card's colors follow the draft. A slow one (taken from a picture)
  /// that finishes after a newer one is dropped.
  Future<void> refreshCardScheme() async {
    final viewer = Theme.of(context).brightness;
    final fallback = nameColorFor(viewer);
    final inputs = (
      viewer,
      fallback,
      draft.cardColor,
      draft.cardBrightness,
      draft.banner,
      draft.picture
    );
    if (inputs == cardSchemeInputs) return;
    cardSchemeInputs = inputs;

    final scheme = await profileCardColorScheme(
      viewerBrightness: viewer,
      fallbackColor: fallback,
      color: draft.cardColor,
      brightness: draft.cardBrightness,
      banner: draft.banner,
      avatar: draft.picture,
    );
    if (!mounted || cardSchemeInputs != inputs) return;
    setState(() => cardScheme = scheme);
  }

  /// The color our name is drawn in by people on [brightness] themes.
  Color nameColorFor(Brightness brightness) =>
      draft.nameColor?.forBrightness(brightness) ??
      MatrixMember.hashColor(selfId);

  Future<void> writeStatus(_Draft d) async {
    final text = d.status.trim();
    await component.setStatus(text.isEmpty ? null : text);
    // The profile field is what every card reads; presence is a bonus on the
    // homeservers that share it, and some refuse it.
    try {
      await widget.client.getComponent<UserPresenceComponent>()?.setStatus(
          UserIdleWatcher.instance.status.value,
          message: text.isEmpty ? null : text,
          clearMessage: text.isEmpty);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not put our status in our presence");
    }
  }

  Future<void> save() async {
    final snapshot = draft.copy();
    setState(() {
      saving = true;
      saveFailed = false;
    });

    final written = <_Part>[];
    var failed = false;
    for (final part in parts) {
      if (_same(part.value(snapshot), part.value(saved))) continue;
      try {
        await part.write(snapshot);
        written.add(part);
      } catch (e, s) {
        Log.onError(e, s, content: "Could not save a profile change");
        failed = true;
      }
    }

    // What we wrote is the new baseline; the fresh profile is for the raw
    // view and for drawing the saved bio.
    final fresh = await component.getProfile(selfId);
    if (!mounted) return;
    setState(() {
      for (final part in written) {
        part.copy(snapshot, saved);
      }
      profile = fresh;
      saving = false;
      saveFailed = failed;
    });
  }

  void reset() {
    edit(() {
      draft = saved.copy();
      saveFailed = false;
      fillControllers();
    });
  }

  Future<void> pickPicture() async {
    final bytes = await PickerUtils.pickImageAndCrop(context, aspectRatio: 1);
    if (bytes == null || !mounted) return;
    edit(() => draft.picture = MemoryImage(bytes));
  }

  Future<void> pickBanner() async {
    final bytes =
        await PickerUtils.pickImageAndCrop(context, aspectRatio: 700 / 230);
    if (bytes == null || !mounted) return;
    edit(() => draft.banner = MemoryImage(bytes));
  }

  Future<void> removeColorOverride() async {
    await ErrorUtils.tryRun(context, () => colors!.setColor(selfId, null));
    if (!mounted) return;
    setState(() => colorOverride = colors?.getOverride(selfId));
  }

  void showSource() {
    AdaptiveDialog.show(
      context,
      title: promptProfileSettingsViewRawProfile,
      builder: (context) => SizedBox(
        width: 1000,
        child: SelectionArea(
          child: ExpandableCodeBlock(
              expanded: true, text: profile!.source, language: "json"),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());

    final intro = tiamat.Text.label(labelProfileSettingsIntro);
    Widget form({required bool withIntro}) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            if (withIntro) intro,
            pictureAndBanner(context),
            names(),
            aboutYou(),
            colorsPanel(context),
            if (availableBadges.isNotEmpty) badges(),
            if (preferences.developerMode.value)
              Align(
                alignment: Alignment.centerLeft,
                child: tiamat.Button.secondary(
                    text: promptProfileSettingsViewRawProfile,
                    onTap: showSource),
              ),
          ],
        );

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      // Nothing above this page makes room for the keyboard.
      return Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).scale().viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 20,
                      children: [
                        Expanded(
                            child: SingleChildScrollView(
                                child: form(withIntro: true))),
                        SizedBox(
                            width: 380,
                            child:
                                SingleChildScrollView(child: preview(context))),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 20,
                        children: [
                          intro,
                          Center(
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 500),
                                child: preview(context)),
                          ),
                          form(withIntro: false),
                        ],
                      ),
                    ),
            ),
            if (dirty) saveBar(context),
          ],
        ),
      );
    });
  }

  Widget preview(BuildContext context) {
    final theme = Theme.of(context);
    final cardTheme =
        cardScheme == null ? theme : theme.copyWith(colorScheme: cardScheme);
    final name = draft.name.trim();
    final status = draft.status.trim();
    final bio = draft.bio.trim();

    Widget? bioView;
    if (bio.isNotEmpty) {
      bioView = switch (profile) {
        // The saved bio, drawn as everyone sees it.
        ProfileWithBio p when p.hasBio && bio == saved.bio.trim() =>
          p.buildBio(context, cardTheme),
        // The draft, as it will be drawn once saved.
        ProfileWithBio p => p.buildBio(context, cardTheme, overrideText: bio),
        _ => Builder(
            builder: (context) => Text(bio,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface))),
      };
    }

    return ProfilePreview(
      cardTheme: cardTheme,
      identifier: selfId,
      displayName: name.isEmpty ? saved.name : name,
      nameColor: nameColorFor(theme.brightness),
      placeholderColor: nameColorFor(cardTheme.brightness),
      picture: draft.picture,
      banner: draft.banner,
      pronouns: [if (draft.pronouns.trim().isNotEmpty) draft.pronouns.trim()],
      presence: status.isEmpty
          ? null
          : UserPresence(UserIdleWatcher.instance.status.value,
              message:
                  UserPresenceMessage(status, PresenceMessageType.userCustom)),
      bio: bioView,
      timezone: draft.timezone,
      badges: draft.badges.toList(),
    );
  }

  Widget panel(String header, List<Widget> children) {
    return tiamat.Panel(
      header: header,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: children,
        ),
      ),
    );
  }

  Widget titled(String title, String description, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        tiamat.Text.labelEmphasised(title),
        tiamat.Text.labelLow(description),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }

  Widget imageButtons(
      {required bool hasImage,
      required Future<void> Function() onChange,
      required VoidCallback onRemove}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        tiamat.Button.secondary(
            text: promptProfileSettingsChangeImage, onTap: onChange),
        if (hasImage)
          tiamat.Button.danger(
              text: CommonStrings.promptRemove, onTap: onRemove),
      ],
    );
  }

  Widget pictureAndBanner(BuildContext context) {
    return panel(labelProfileSettingsPictureAndBanner, [
      Row(
        spacing: 16,
        children: [
          tiamat.Avatar.large(
            image: draft.picture,
            placeholderText: draft.name.trim().isEmpty ? selfId : draft.name,
            placeholderColor: nameColorFor(Theme.of(context).brightness),
          ),
          Expanded(
            child: titled(labelProfileSettingsPicture,
                labelProfileSettingsPictureDescription, [
              imageButtons(
                  hasImage: draft.picture != null,
                  onChange: pickPicture,
                  onRemove: () => edit(() => draft.picture = null)),
            ]),
          ),
        ],
      ),
      titled(
          labelProfileSettingsBanner, labelProfileSettingsBannerDescription, [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 700 / 230,
              child: draft.banner != null
                  ? Image(image: draft.banner!, fit: BoxFit.cover)
                  : ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: draft.picture == null
                          ? null
                          : Center(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: tiamat.Text.labelLow(
                                    labelProfileSettingsNoBanner),
                              ),
                            ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        imageButtons(
            hasImage: draft.banner != null,
            onChange: pickBanner,
            onRemove: () => edit(() => draft.banner = null)),
      ]),
    ]);
  }

  Widget field({
    Key? key,
    required TextEditingController controller,
    required String label,
    required String helper,
    required ValueChanged<String> onChanged,
    String? hint,
    String? error,
    int? maxLength,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextField(
      key: key,
      controller: controller,
      onChanged: (value) => edit(() => onChanged(value)),
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 8,
        errorText: error,
        errorMaxLines: 2,
      ),
    );
  }

  Widget names() {
    return panel(labelProfileSettingsName, [
      field(
        key: ProfileEditor.nameFieldKey,
        controller: nameController,
        label: labelProfileSettingsDisplayName,
        helper: labelProfileSettingsDisplayNameDescription(selfId),
        error: nameMissing ? errorProfileSettingsDisplayNameEmpty : null,
        maxLength: 256,
        onChanged: (value) => draft.name = value,
      ),
      field(
        controller: pronounsController,
        label: labelProfileSettingsPronouns,
        hint: labelProfileSettingsPronounsHint,
        helper: labelProfileSettingsPronounsDescription,
        onChanged: (value) => draft.pronouns = value,
      ),
    ]);
  }

  Widget aboutYou() {
    final timezone = draft.timezone ?? saved.timezone ?? deviceTimezone;
    return panel(labelProfileSettingsAboutYou, [
      field(
        controller: statusController,
        label: labelProfileSettingsStatus,
        helper: labelProfileSettingsStatusDescription,
        maxLength: 128,
        onChanged: (value) => draft.status = value,
      ),
      field(
        controller: bioController,
        label: labelProfileSettingsAboutMe,
        helper: labelProfileSettingsAboutMeDescription,
        minLines: 3,
        maxLines: 10,
        onChanged: (value) => draft.bio = value,
      ),
      if (timezone != null)
        SettingsEntryBool(
          draft.timezone != null,
          title: labelProfileSettingsShowLocalTime,
          description: labelProfileSettingsShowLocalTimeDescription(timezone),
          onChanged: (on) => edit(() =>
              draft.timezone = on ? saved.timezone ?? deviceTimezone : null),
        ),
      if (draft.timezone != null &&
          deviceTimezone != null &&
          draft.timezone != deviceTimezone)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            tiamat.Text.labelLow(labelProfileSettingsTimezoneDiffers(
                draft.timezone!, deviceTimezone!)),
            tiamat.Button.secondary(
                text: promptProfileSettingsUseDeviceTimezone,
                onTap: () => edit(() => draft.timezone = deviceTimezone)),
          ],
        ),
    ]);
  }

  Widget colorsPanel(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    // A color picked elsewhere (another app, or Rooster's old free picker)
    // stays on offer until something else is picked.
    final nameColors = [
      ...namePalette,
      if (saved.nameColor != null && !namePalette.contains(saved.nameColor))
        saved.nameColor!,
    ];
    final seeds = namePalette.map((c) => c.onLight).toList();
    if (saved.cardColor != null && !seeds.contains(saved.cardColor)) {
      seeds.add(saved.cardColor!);
    }

    Widget dot(Color color) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle));

    Widget style(String label, Brightness? value) => ChoiceChip(
          label: Text(label),
          selected: draft.cardBrightness == value,
          onSelected: (_) => edit(() => draft.cardBrightness = value),
        );

    return panel(labelProfileSettingsColors, [
      titled(labelProfileSettingsNameColor,
          labelProfileSettingsNameColorDescription, [
        ProfileColorPicker(
          id: "profile-name-color",
          colors: [for (final c in nameColors) c.forBrightness(brightness)],
          selected: draft.nameColor == null
              ? null
              : nameColors.indexOf(draft.nameColor!),
          automaticIcon: dot(MatrixMember.hashColor(selfId)),
          onSelected: (i) =>
              edit(() => draft.nameColor = i == null ? null : nameColors[i]),
        ),
        if (colorOverride != null) ...[
          const SizedBox(height: 8),
          Row(
            spacing: 8,
            children: [
              dot(colorOverride!),
              Expanded(
                child:
                    tiamat.Text.labelLow(labelProfileSettingsColorOverrideNote),
              ),
            ],
          ),
          tiamat.Button.secondary(
              text: CommonStrings.promptRemove, onTap: removeColorOverride),
        ],
      ]),
      titled(labelProfileSettingsCardColors,
          labelProfileSettingsCardColorsDescription, [
        ProfileColorPicker(
          id: "profile-card-color",
          colors: seeds,
          selected:
              draft.cardColor == null ? null : seeds.indexOf(draft.cardColor!),
          automaticIcon: const Icon(Icons.wallpaper, size: 18),
          onSelected: (i) => edit(() {
            draft.cardColor = i == null ? null : seeds[i];
            if (i == null) draft.cardBrightness = null;
          }),
        ),
        if (draft.cardColor != null) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              style(labelProfileSettingsCardMatchTheme, null),
              style(labelProfileSettingsCardAlwaysDark, Brightness.dark),
              style(labelProfileSettingsCardAlwaysLight, Brightness.light),
            ],
          ),
        ],
      ]),
    ]);
  }

  Widget badges() {
    return panel(labelProfileSettingsBadges, [
      tiamat.Text.labelLow(labelProfileSettingsBadgesDescription),
      for (final badge in availableBadges)
        CheckboxListTile(
          value: draft.badges.contains(badge),
          onChanged: (on) => edit(() => draft.badges = on == true
              ? {...draft.badges, badge}
              : ({...draft.badges}..remove(badge))),
          secondary:
              SizedBox(width: 30, height: 30, child: Image(image: badge.image)),
          title: Text(badge.body),
        ),
    ]);
  }

  Widget saveBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  tiamat.Text.labelEmphasised(
                      labelProfileSettingsUnsavedChanges),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      tiamat.Button.secondary(
                          text: CommonStrings.promptReset,
                          onTap: saving ? null : reset),
                      tiamat.Button(
                          key: ProfileEditor.saveKey,
                          text: promptProfileSettingsSaveChanges,
                          isLoading: saving,
                          onTap: nameMissing ? null : save),
                    ],
                  ),
                ],
              ),
              if (saveFailed) tiamat.Text.error(errorProfileSettingsSaveFailed),
            ],
          ),
        ),
      ),
    );
  }
}
