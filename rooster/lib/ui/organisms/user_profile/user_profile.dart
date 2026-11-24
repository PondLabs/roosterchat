import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/direct_messages/direct_message_component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/user_color/user_color_component.dart';
import 'package:rooster/client/components/user_presence/user_presence_component.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/atoms/code_block.dart';
import 'package:rooster/ui/atoms/e2ee_trust_shield.dart';
import 'package:rooster/ui/atoms/inherited_offstage.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/navigation/navigation_utils.dart';
import 'package:rooster/ui/molecules/profile/e2ee_trust.dart';
import 'package:rooster/ui/organisms/user_profile/mutual_rooms_view.dart';
import 'package:rooster/ui/organisms/user_profile/profile_card_theme.dart';
import 'package:rooster/ui/organisms/user_profile/user_devices.dart';
import 'package:rooster/ui/pages/matrix/verification/matrix_verification_page.dart';
import 'package:rooster/ui/pages/settings/app_settings_page.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:rooster/ui/organisms/user_profile/user_profile_view.dart';
import 'package:rooster/ui/organisms/moderation/profile_moderation_actions.dart';
import 'package:rooster/utils/timezone_utils.dart';
import 'package:rooster/client/components/petname/petname_component.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

class UserProfile extends StatefulWidget {
  const UserProfile(
      {super.key,
      required this.userId,
      this.width = 700,
      this.bannerHeight = 230.0,
      required this.client,
      this.maxBioHeight = 200,
      this.doSafeArea = true,
      this.showMessageButton = true});
  final Client client;
  final String userId;
  final double bannerHeight;
  final double width;
  final double maxBioHeight;
  final bool doSafeArea;
  final bool showMessageButton;

  @override
  State<UserProfile> createState() => _UserProfileState();

  static Future<T?> show<T extends Object?>(
    BuildContext context, {
    required Client client,
    required String userId,
    bool dismissible = true,
  }) async {
    if (MediaQuery.sizeOf(context).desktop)
      return showGeneralDialog(
          context: context,
          pageBuilder: (context, animation, secondaryAnimation) {
            return Theme(
              data: Theme.of(context),
              child: Center(child: UserProfile(userId: userId, client: client)),
            );
          },
          // Read out by screen readers: tapping outside closes the profile.
          barrierLabel:
              MaterialLocalizations.of(context).modalBarrierDismissLabel,
          barrierDismissible: dismissible,
          transitionDuration: const Duration(milliseconds: 300),
          transitionBuilder: (context, animation, secondaryAnimation, child) =>
              SlideTransition(
                position:
                    Tween(begin: const Offset(0, 1), end: const Offset(0, 0))
                        .animate(CurvedAnimation(
                            parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              ));

    return showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      useSafeArea: false,
      builder: (context) {
        return UserProfile(
          userId: userId,
          client: client,
          width: double.infinity,
        );
      },
    );
  }
}

class _UserProfileState extends State<UserProfile> {
  Profile? profile;
  ThemeData? theme;

  String get labelProfileSourceTitle => Intl.message("Source",
      name: "labelProfileSourceTitle",
      desc: "Title of the dialog that shows the raw JSON of a user's profile "
          "(developer mode)");

  ImageProvider? banner;
  ImageProvider? avatar;
  UserPresence? presence;
  String? timezone;
  List<String> pronouns = const [];
  List<ProfileBadge> badges = [];

  @override
  void initState() {
    super.initState();
    loadProfile();
    loadDeviceKeys();
  }

  /// The Matrix client whose keys this card shows: none for ourselves, or
  /// without encryption.
  matrix.Client? get encryptedClient {
    final client = widget.client;
    if (client is! MatrixClient) return null;
    final mx = client.matrixClient;
    if (!mx.encryptionEnabled || widget.userId == mx.userID) return null;
    return mx;
  }

  /// Asks for their device keys when we have none or they are stale.
  Future<void> loadDeviceKeys() async {
    final mx = encryptedClient;
    final userId = widget.userId;
    if (mx == null || mx.userDeviceKeys[userId]?.outdated == false) return;
    try {
      await mx.updateUserDeviceKeys(additionalUsers: {userId});
    } catch (e, s) {
      Log.onError(e, s, content: "Could not fetch a user's device keys");
    }
    if (mounted && widget.userId == userId) setState(() {});
  }

  @override
  void didUpdateWidget(UserProfile oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.userId != widget.userId ||
        oldWidget.client != widget.client) {
      profile = null;
      loadProfile();
      loadDeviceKeys();
    }
  }

  Future<void> loadProfile() async {
    final client = widget.client;
    final userId = widget.userId;
    // Closed, or now showing someone else: this load's result is not wanted.
    bool stale() =>
        !mounted || widget.client != client || widget.userId != userId;

    final value =
        await client.getComponent<UserProfileComponent>()!.getProfile(userId);
    if (stale()) return;

    final banner = value.banner;
    var avatar = value.avatar;

    if (avatar case MatrixMxcImage mxc) {
      // create a new image instance so we can load fullres without it loading everywhere
      avatar = MatrixMxcImage(mxc.identifier, mxc.client,
          doThumbnail: false, doFullres: true, autoLoadFullRes: true);
    }

    var badges = <ProfileBadge>[];
    if (value case ProfileWithBadges p) {
      badges = await p.getBadges();
      if (stale()) return;
    }

    await TimezoneUtils.instance.init();
    if (stale()) return;

    Color? color;
    Brightness? brightness;
    if (value case ProfileWithColorScheme p) {
      color = p.color;
      brightness = p.brightness;
    }

    final scheme = await profileCardColorScheme(
      viewerBrightness: Theme.of(context).brightness,
      fallbackColor: value.defaultColor,
      color: color,
      brightness: brightness,
      banner: banner,
      avatar: value.avatar,
    );
    if (stale()) return;

    try {
      await Future.wait<dynamic>([
        if (banner != null) precacheImage(banner, context),
        if (avatar != null) precacheImage(avatar, context),
      ]).timeout(Duration(seconds: 5));
    } catch (e, s) {
      Log.onError(e, s, content: "Error while fetching profile images");
    }
    if (stale()) return;

    setState(() {
      theme = Theme.of(context).copyWith(colorScheme: scheme);
      profile = value;
      this.banner = banner;
      this.avatar = avatar;
      this.badges = badges;
      timezone = null;
      pronouns = const [];
      presence = null;

      if (value case ProfileWithTimezone p) {
        timezone = p.timezone;
      }

      if (value case ProfileWithPronouns p) {
        pronouns = p.pronouns;
      }

      if (value case ProfileWithPresence p) {
        presence = p.precence;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    if (profile == null) {
      return SizedBox(
          height: 300, child: const Center(child: CircularProgressIndicator()));
    }

    Widget? bio;

    if (profile case ProfileWithBio p) {
      if (p.hasBio) {
        bio = p.buildBio(context, theme!);
      }
    }

    if (InheritedOffstage.isOffstage(context)) {
      return Placeholder();
    }

    final verification =
        widget.client.getComponent<MatrixKeyVerificationComponent>();
    final canVerify =
        verification != null && verification.canVerifyUser(profile.identifier);

    final mx = encryptedClient;
    if (mx == null) return buildView(profile, bio, canVerify: canVerify);
    return E2eeTrustBuilder(
      client: mx,
      compute: (identities) => E2eeTrustResolver.forUser(mx, profile.identifier,
          identities: identities),
      builder: (context, trust, identities) => buildView(profile, bio,
          canVerify: canVerify,
          trust: trust,
          devices: UserDevices.of(mx, profile.identifier),
          onSetDeviceBlocked: (deviceId, blocked) =>
              setDeviceBlocked(mx, deviceId, blocked),
          onWithdrawVerification: identities == null
              ? null
              : () => identities.forget(profile.identifier)),
    );
  }

  Widget buildView(Profile profile, Widget? bio,
      {required bool canVerify,
      E2eeTrust? trust,
      List<UserDevice> devices = const [],
      Future<void> Function(String deviceId, bool blocked)? onSetDeviceBlocked,
      Future<void> Function()? onWithdrawVerification}) {
    return Theme(
      data: theme!,
      child: UserProfileView(
        userAvatar: avatar,
        displayName: profile.displayName,
        identifier: profile.identifier,
        userColor: profile.defaultColor,
        userBanner: banner,
        presence: presence,
        timezone: timezone,
        bannerHeight: widget.bannerHeight,
        width: widget.width,
        doSafeArea: widget.doSafeArea,
        maxBioHeight: widget.maxBioHeight,
        showMessageButton: widget.showMessageButton,
        isSelf: widget.client.self!.identifier == profile.identifier,
        onMessageButtonClicked: openDirectMessage,
        onVerifyUser: canVerify ? verifyUser : null,
        trust: trust,
        devices: devices,
        onSetDeviceBlocked: onSetDeviceBlocked,
        onWithdrawVerification: onWithdrawVerification,
        mutualRooms: MutualRoomsView.forUser(widget.client, profile.identifier),
        // Only from the popup: the card shown inside a page has nothing to
        // close first.
        onEditProfile:
            ModalRoute.of(context) is PopupRoute ? editProfile : null,
        badges: badges,
        bio: bio,
        setPetName: setPetName,
        currentPetName: widget.client
            .getComponent<PetNameComponent>()
            ?.getPetName(widget.userId),
        setColorOverride: setColorOverride,
        showSource: showSource,
        pronouns: pronouns,
        hasColorOverride: widget.client
                .getComponent<UserColorComponent>()
                ?.getOverride(profile.identifier) !=
            null,
        moderationActions: ProfileModerationActions.of(
            context, widget.client, profile.identifier,
            displayName: profile.displayName, onChanged: () {
          if (mounted) setState(() {});
        }),
      ),
    );
  }

  /// Blocks or unblocks one of their devices, then shows it.
  Future<void> setDeviceBlocked(
      matrix.Client mx, String deviceId, bool blocked) async {
    await ErrorUtils.tryRun(context, () async {
      await UserDevices.setBlocked(mx, widget.userId, deviceId, blocked);
    });
    if (mounted) setState(() {});
  }

  Future<void> openDirectMessage() async {
    final component = widget.client.getComponent<DirectMessagesComponent>();
    if (component == null) {
      return;
    }

    var existingRooms = component.directMessageRooms.where((element) =>
        profile!.identifier == component.getDirectMessagePartnerId(element));

    if (existingRooms.isNotEmpty == true) {
      EventBus.doOpenRoom(existingRooms.first.identifier,
          clientId: widget.client.identifier);
    } else {
      var room = await component.createDirectMessage(profile!.identifier);
      if (room != null) {
        EventBus.doOpenRoom(room.identifier,
            clientId: widget.client.identifier);
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> verifyUser() async {
    final verification =
        widget.client.getComponent<MatrixKeyVerificationComponent>();
    final target = profile;
    if (verification == null || target == null) return;

    await ErrorUtils.tryRun(context, () async {
      final request =
          await verification.startUserVerification(target.identifier);
      if (!mounted) return;
      await AdaptiveDialog.show(
        context,
        title: MatrixKeyVerificationComponent.labelAppVerificationRequest,
        builder: (_) => MatrixVerificationPage(
          request: request,
          component: verification,
        ),
      );
    });
  }

  /// Closes the card, then opens Settings on this account's profile.
  Future<void> editProfile() {
    final navigator = Navigator.of(context);
    navigator.pop();
    return NavigationUtils.navigateTo(
        navigator.context, AppSettingsPage(editProfileOf: widget.client));
  }

  Future<void> setColorOverride(Color? color) async {
    var comp = widget.client.getComponent<UserColorComponent>();
    await comp?.setColor(widget.userId, color);
    if (mounted) setState(() {}); // repaint in the new color
  }

  Future<void> setPetName(String? name) async {
    var comp = widget.client.getComponent<PetNameComponent>();
    await comp?.setPetName(widget.userId, name);
    if (mounted) setState(() {}); // refresh so the view shows the new name
  }

  void showSource() {
    AdaptiveDialog.show(
      context,
      title: labelProfileSourceTitle,
      builder: (context) {
        return SizedBox(
          width: 1000,
          child: SelectionArea(
            child: ExpandableCodeBlock(
                expanded: true, text: profile!.source, language: "json"),
          ),
        );
      },
    );
  }
}
