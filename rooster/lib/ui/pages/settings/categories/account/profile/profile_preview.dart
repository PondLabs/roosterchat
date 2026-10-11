import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/user_presence/user_presence_component.dart';
import 'package:rooster/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:rooster/ui/organisms/user_profile/user_profile_view.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What Settings > Profile shows of the draft: the card as other people see
/// it, and one message of ours in a chat.
class ProfilePreview extends StatelessWidget {
  const ProfilePreview({
    super.key,
    required this.cardTheme,
    required this.identifier,
    required this.displayName,
    required this.nameColor,
    required this.placeholderColor,
    this.picture,
    this.banner,
    this.pronouns = const [],
    this.presence,
    this.bio,
    this.timezone,
    this.badges = const [],
  });

  final ThemeData cardTheme;
  final String identifier;
  final String displayName;

  /// The color of our name in the chat, for the app's current theme.
  final Color nameColor;
  final Color placeholderColor;
  final ImageProvider? picture;
  final ImageProvider? banner;
  final List<String> pronouns;
  final UserPresence? presence;
  final Widget? bio;
  final String? timezone;
  final List<ProfileBadge> badges;

  static String get labelProfileSettingsPreview => Intl.message("Preview",
      name: "labelProfileSettingsPreview",
      desc: "Settings > Profile: heading over the preview of the user's "
          "profile card, as other people will see it");

  static String get labelProfileSettingsPreviewInChat => Intl.message("In chat",
      name: "labelProfileSettingsPreviewInChat",
      desc: "Settings > Profile: heading over a sample chat message that "
          "shows how the user's name, picture and name color look in a chat");

  static String get labelProfileSettingsSampleMessage => Intl.message(
      "Hey crew, who's around tonight?",
      name: "labelProfileSettingsSampleMessage",
      desc: "Settings > Profile: a made-up chat message, sent by the user, in "
          "the preview of how their name looks in a chat. Casual, friendly");

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          tiamat.Text.labelLow(labelProfileSettingsPreview),
          Theme(
            data: cardTheme,
            child: UserProfileView(
              preview: true,
              isSelf: false,
              showMessageButton: false,
              doSafeArea: false,
              width: width,
              bannerHeight: width * 230 / 700,
              maxBioHeight: 200,
              identifier: identifier,
              displayName: displayName,
              userColor: placeholderColor,
              userAvatar: picture,
              userBanner: banner,
              pronouns: pronouns,
              presence: presence,
              bio: bio,
              timezone: timezone,
              badges: badges,
            ),
          ),
          const SizedBox(height: 4),
          tiamat.Text.labelLow(labelProfileSettingsPreviewInChat),
          Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
              child: TimelineEventLayoutMessage(
                senderName: displayName,
                senderColor: nameColor,
                senderAvatar: picture,
                timestamp: MaterialLocalizations.of(context)
                    .formatTimeOfDay(TimeOfDay.now()),
                formattedContent:
                    tiamat.Text.body(labelProfileSettingsSampleMessage),
              ),
            ),
          ),
        ],
      );
    });
  }
}
