import 'dart:async';
import 'dart:ui';

import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/user_presence/user_presence_component.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/adaptive_context_menu.dart';
import 'package:rooster/ui/atoms/scaled_safe_area.dart';
import 'package:rooster/ui/atoms/tiny_pill.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:timezone/standalone.dart' as tz;

class UserProfileView extends StatefulWidget {
  const UserProfileView(
      {super.key,
      this.userAvatar,
      required this.displayName,
      required this.userColor,
      this.userBanner,
      required this.identifier,
      required this.isSelf,
      this.presence,
      this.timezone,
      this.bannerHeight = 230.0,
      this.width = 700,
      this.hasColorOverride = false,
      this.setColorOverride,
      this.setPetName,
      this.currentPetName,
      this.bio,
      this.badges = const [],
      this.showMessageButton = true,
      this.doSafeArea = true,
      this.maxBioHeight = 200,
      this.showSource,
      this.pronouns = const [],
      this.preview = false,
      this.onEditProfile,
      this.onMessageButtonClicked});
  final ImageProvider? userAvatar;
  final ImageProvider? userBanner;
  final UserPresence? presence;
  final String displayName;
  final String identifier;
  final bool doSafeArea;
  final List<String> pronouns;
  final List<ProfileBadge> badges;
  final Color userColor;
  final bool isSelf;
  final bool showMessageButton;
  final double bannerHeight;
  final double maxBioHeight;
  final bool hasColorOverride;
  final String? timezone;
  final double width;
  final void Function()? showSource;
  final Widget? bio;
  final Future<void> Function(String?)? setPetName;
  final String? currentPetName;
  final Future<void> Function()? onMessageButtonClicked;
  final Future<void> Function(Color?)? setColorOverride;

  /// Draws the card as others see it, for a preview: no menu, nothing to
  /// tap, no buttons.
  final bool preview;

  /// Shown as an "Edit profile" button on your own card.
  final Future<void> Function()? onEditProfile;

  @override
  State<UserProfileView> createState() => UserProfileViewState();
}

class UserProfileViewState extends State<UserProfileView> {
  bool isLoadingDirectMessage = false;

  String get promptOpenDirectMessage => Intl.message("Message",
      desc: "Prompt on the button to open a direct message with another user",
      name: "promptOpenDirectMessage");

  String get promptProfileEditProfile => Intl.message("Edit profile",
      name: "promptProfileEditProfile",
      desc: "Button on the user's own profile card: opens Settings on their "
          "profile, where they change what others see");

  String get promptProfileRecolorName => Intl.message("Recolor their name",
      name: "promptProfileRecolorName",
      desc: "Entry in the menu of someone else's profile card, and the title "
          "of its dialog: pick the color their name shows in, only for the "
          "user");

  String get promptProfileShowRawProfile => Intl.message("Show Raw Profile",
      name: "promptProfileShowRawProfile",
      desc:
          "Show the raw data of a user profile, typically this is hidden behind developer mode");

  String labelProfileLocalTime(String day, String time) =>
      Intl.message("$day, $time",
          name: "labelProfileLocalTime",
          args: [day, time],
          desc: "The time where a user is, on their profile, when it is "
              "another day there: the weekday, then the time");

  String tooltipProfileLocalTimezone(String timezone) =>
      Intl.message("Local Timezone: $timezone",
          name: "tooltipProfileLocalTimezone",
          args: [timezone],
          desc: "Tooltip of the user's local time on their profile, with "
              "their timezone (such as America/Sao_Paulo)");

  String get labelProfileRecolorDescription => Intl.message(
      "Only you see this color, on all your devices. Everyone else sees the color they chose, or the automatic one.",
      name: "labelProfileRecolorDescription",
      desc: "In the dialog that picks the color someone else's name shows in "
          "for the user, above the colors");

  String get promptProfileGiveNickname => Intl.message("Give them a nickname",
      name: "promptProfileGiveNickname",
      desc: "Entry in the menu of someone else's profile card: opens a dialog "
          "to give them a name only the user sees");

  String get labelProfileNickname => Intl.message("Nickname",
      name: "labelProfileNickname",
      desc: "Title of the dialog where the user types the nickname they give "
          "someone");

  String get labelProfileNicknameDescription => Intl.message(
      "Only you see this nickname, on all your devices. Everyone else sees the name they chose.",
      name: "labelProfileNicknameDescription",
      desc: "In the dialog where the user gives someone a nickname, above the "
          "text field");

  Timer? timezoneTimer;

  tz.TZDateTime? localTime;

  ScrollController bioScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    startClock();
  }

  @override
  void didUpdateWidget(UserProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timezone != widget.timezone) startClock();
  }

  @override
  void dispose() {
    timezoneTimer?.cancel();
    super.dispose();
  }

  void startClock() {
    timezoneTimer?.cancel();
    timezoneTimer = null;
    localTime = null;
    if (widget.timezone == null) return;

    timezoneTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(updateLocalTime));
    updateLocalTime();
  }

  void updateLocalTime() {
    final timezone = widget.timezone;
    if (timezone == null) return;

    try {
      localTime = tz.TZDateTime.now(tz.getLocation(timezone));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    var background = Theme.of(context).colorScheme.primaryContainer;
    final bannerHeight = widget.bannerHeight;
    const avatarOverlap = 50.0;
    final menuItems = contextMenuItems(context);

    return ClipRRect(
      borderRadius: BorderRadiusGeometry.circular(8),
      child: Container(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.width),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 0,
            children: [
              SizedBox(
                child: Stack(
                  children: [
                    SizedBox(
                      height: bannerHeight,
                      width: double.infinity,
                      child: widget.userBanner != null
                          ? Image(
                              image: widget.userBanner!,
                              fit: BoxFit.cover,
                            )
                          : widget.userAvatar != null
                              ? ClipRect(
                                  child: ImageFiltered(
                                    imageFilter: ImageFilter.blur(
                                        sigmaX: 40,
                                        sigmaY: 40,
                                        tileMode: TileMode.repeated),
                                    child: Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainer,
                                      child: Image(
                                        image: widget.userAvatar!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                                ),
                    ),
                    if (menuItems.isNotEmpty)
                      Align(
                          alignment: AlignmentGeometry.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: ClipRRect(
                              borderRadius: BorderRadiusGeometry.circular(15),
                              child: SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: Material(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withAlpha(100),
                                    child: AdaptiveContextMenu(
                                      modal: true,
                                      items: menuItems,
                                      child: Icon(
                                        Icons.more_vert,
                                        size: 15,
                                      ),
                                    ),
                                  )),
                            ),
                          )),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          0, bannerHeight - avatarOverlap, 0, 0),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                0, avatarOverlap - 2, 0, 0),
                            child: Container(
                              color: background,
                              child: ScaledSafeArea(
                                  bottom: widget.doSafeArea,
                                  top: widget.doSafeArea,
                                  left: widget.doSafeArea,
                                  right: widget.doSafeArea,
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                        8, avatarOverlap, 8, 8),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainer,
                                      ),
                                      child: Column(
                                        spacing: 8,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      12, 4, 12, 4),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Flexible(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        displayName(),
                                                        username(context),
                                                        pronouns(),
                                                      ],
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding: const EdgeInsets
                                                        .fromLTRB(0, 8, 0, 0),
                                                    child: Column(
                                                      spacing: 8,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                      children: [
                                                        if (localTime != null &&
                                                            widget.timezone !=
                                                                null)
                                                          userLocalTime(),
                                                        if (widget
                                                            .badges.isNotEmpty)
                                                          badges(),
                                                      ],
                                                    ),
                                                  )
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (widget.bio != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      8, 0, 8, 0),
                                              child: buildBio(context),
                                            ),
                                          if (!widget.preview &&
                                              !widget.isSelf &&
                                              widget.showMessageButton)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: tiamat.Button(
                                                text: promptOpenDirectMessage,
                                                isLoading:
                                                    isLoadingDirectMessage,
                                                onTap: clickMessageButton,
                                              ),
                                            ),
                                          if (!widget.preview &&
                                              widget.isSelf &&
                                              widget.onEditProfile != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: tiamat.Button(
                                                text: promptProfileEditProfile,
                                                onTap: widget.onEditProfile,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  )),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                tiamat.Avatar.large(
                                  border: BoxBorder.all(
                                      color: background,
                                      width: 8,
                                      strokeAlign: 0.9),
                                  image: widget.userAvatar,
                                  placeholderColor: widget.userColor,
                                  placeholderText: widget.displayName,
                                ),
                                if (widget.presence?.message != null)
                                  Flexible(
                                      child: buildPresenceDisplay(background))
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Padding username(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      child: Opacity(
          opacity: 0.8,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  widget.identifier,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontFamily: "Code",
                      color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
              if (!widget.preview)
                tiamat.IconButton(
                  icon: Icons.copy,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: widget.identifier)),
                  size: Theme.of(context).textTheme.labelSmall?.fontSize ?? 12,
                  iconColor: Theme.of(context).colorScheme.onSurface,
                ),
            ],
          )),
    );
  }

  Container buildBio(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxBioHeight),
              child: Scrollbar(
                thumbVisibility: true,
                controller: bioScrollController,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(0),
                  controller: bioScrollController,
                  child: widget.bio,
                ),
              ),
            )));
  }

  Widget userLocalTime() {
    final l = localTime!;
    var t = DateTime(l.year, l.month, l.day, l.hour, l.minute, l.second);

    var use24 = PlatformUtils.isAndroid
        ? MediaQuery.of(context).alwaysUse24HourFormat
        : false;
    var localDay = DateFormat(DateFormat.WEEKDAY).format(DateTime.now());
    var day = DateFormat(DateFormat.WEEKDAY).format(t);
    var time = MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(t),
        alwaysUse24HourFormat: use24);

    var result = time;
    if (day != localDay) {
      result = labelProfileLocalTime(day, time);
    }

    final colors = Theme.of(context).colorScheme;
    return tiamat.Tooltip(
      child: TinyPill(result,
          background: colors.tertiary, foreground: colors.onTertiary),
      text: tooltipProfileLocalTimezone(widget.timezone!),
    );
  }

  /// Only for other people: the things about them only you see. Your own
  /// card has none (you edit your profile in Settings), nor does a preview.
  List<tiamat.ContextMenuItem> contextMenuItems(BuildContext context) {
    if (widget.preview || widget.isSelf) return [];

    return [
      if (widget.setPetName != null)
        profileMenuItem(
          text: promptProfileGiveNickname,
          icon: Icons.badge,
          onClearPressed: widget.currentPetName != null
              ? () => widget.setPetName!(null)
              : null,
          onPressed: () async {
            final text = await AdaptiveDialog.textPrompt(
              context,
              initialText: widget.currentPetName,
              title: labelProfileNickname,
              description: labelProfileNicknameDescription,
            );
            if (text != null) {
              await widget.setPetName
                  ?.call(text.trim().isEmpty ? null : text.trim());
            }
          },
        ),
      if (widget.setColorOverride != null)
        profileMenuItem(
          text: promptProfileRecolorName,
          icon: Icons.colorize,
          onClearPressed: widget.hasColorOverride
              ? () => widget.setColorOverride!(null)
              : null,
          onPressed: () async {
            var color = await AdaptiveDialog.show<Color>(
              title: promptProfileRecolorName,
              context,
              builder: (context) {
                return SizedBox(
                  width: 500,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: tiamat.Text.labelLow(
                            labelProfileRecolorDescription),
                      ),
                      GridView(
                          shrinkWrap: true,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisSpacing: 3,
                                  mainAxisSpacing: 3,
                                  crossAxisCount:
                                      MediaQuery.sizeOf(context).mobile
                                          ? 5
                                          : 10),
                          children: [
                            for (int i = 0; i < 20; i++)
                              buildColorSchemeItem(
                                color: HSVColor.fromAHSV(1.0,
                                        (i.toDouble() / 21) * 360, 0.8, 1.0)
                                    .toColor(),
                                onTap: (c) {
                                  Navigator.of(context).pop(c);
                                },
                              )
                          ]),
                    ],
                  ),
                );
              },
            );

            if (color != null) {
              await widget.setColorOverride?.call(color);
            }
          },
        ),
      if (widget.showSource != null && preferences.developerMode.value)
        profileMenuItem(
            text: promptProfileShowRawProfile,
            onPressed: () => widget.showSource?.call(),
            icon: Icons.code),
    ];
  }

  tiamat.ContextMenuItem profileMenuItem(
      {required String text,
      required IconData icon,
      required Function onPressed,
      Function? onClearPressed}) {
    return tiamat.ContextMenuItem(
      text: text,
      icon: icon,
      onPressed: onPressed,
      customBuilder: (context, onClicked, {closeMenu}) {
        var c = Theme.of(context).colorScheme.onSurface;

        return Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.max,
              spacing: 8,
              children: [
                Expanded(
                  child: InkWell(
                      onTap: onClicked,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.max,
                            spacing: 8,
                            children: [
                              Icon(
                                icon,
                                color: c,
                                size: 20,
                              ),
                              Flexible(
                                child: tiamat.Text(text,
                                    type: tiamat.TextType.body,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    color: c),
                              ),
                            ],
                          ))),
                ),
                if (onClearPressed != null)
                  tiamat.IconButton(
                    icon: Icons.close,
                    size: 18,
                    iconColor: Colors.red,
                    onPressed: () {
                      onClearPressed.call();
                      closeMenu?.call();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildColorSchemeItem({
    required Color color,
    required Function(Color) onTap,
  }) {
    return Material(
      clipBehavior: Clip.antiAlias,
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => onTap(color),
        child: const SizedBox(height: 30, width: 30),
      ),
    );
  }

  Widget buildPresenceDisplay(Color background) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Container(
          decoration: BoxDecoration(
              border: BoxBorder.all(color: background, width: 4),
              color: Theme.of(context).colorScheme.secondary,
              borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: tiamat.Text(
              widget.presence!.message!.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              color: Theme.of(context).colorScheme.onSecondary,
            ),
          )),
    );
  }

  Future<void> clickMessageButton() async {
    setState(() {
      isLoadingDirectMessage = true;
    });

    await widget.onMessageButtonClicked?.call();
    if (!mounted) return;

    setState(() {
      isLoadingDirectMessage = false;
    });
  }

  Widget buildBadge(ProfileBadge i) {
    var doOutline = i.brightness == null
        ? false
        : Theme.of(context).brightness == i.brightness;

    return tiamat.Tooltip(
      text: i.body,
      child: SizedBox(
          width: 30,
          height: 30,
          child: Stack(
            children: [
              if (doOutline)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                        Theme.of(context)
                            .colorScheme
                            .inverseSurface
                            .withAlpha(200),
                        BlendMode.srcIn),
                    child: Image(
                      image: i.image,
                    ),
                  ),
                ),
              Image(
                image: i.image,
              ),
            ],
          )),
    );
  }

  Widget displayName() {
    return Text(
      widget.displayName,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface),
    );
  }

  Widget pronouns() {
    if (widget.pronouns.isEmpty) return Container();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: widget.pronouns.map((i) => TinyPill(i)).toList(),
      ),
    );
  }

  Widget badges() {
    return Padding(
        padding: EdgeInsetsGeometry.fromLTRB(2, 2, 2, 2),
        child: Wrap(
          spacing: 8,
          children: widget.badges.map((i) => buildBadge(i)).toList(),
        ));
  }
}
