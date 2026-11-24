import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/moderation/matrix_room_moderation.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/organisms/moderation/moderation_reason_dialog.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The room's banned members, with an unban button for those who may.
class BannedMembersView extends StatefulWidget {
  const BannedMembersView(this.moderation, {super.key});

  final MatrixRoomModeration moderation;

  static String get labelBannedMembers => Intl.message("Banned Members",
      name: "labelBannedMembers",
      desc: "Title of the list of people banned from a room, in its settings");

  static String get labelNoBannedMembers =>
      Intl.message("No one is banned from this room.",
          name: "labelNoBannedMembers",
          desc: "Shown instead of the banned list when it is empty");

  static String get promptUnban => Intl.message("Unban",
      name: "promptUnban",
      desc: "Button next to a banned member: lifts the ban so they can join "
          "again");

  static String messageUnbanConfirmation(String user) =>
      Intl.message("Lift the ban on $user? They will be able to join again.",
          name: "messageUnbanConfirmation",
          args: [user],
          desc: "Asked before unbanning someone, with their name");

  static String labelBanReason(String reason) => Intl.message("Reason: $reason",
      name: "labelBanReason",
      args: [reason],
      desc: "Under a banned member, the reason the moderator gave for the ban");

  static ValueKey<String> unbanKey(String userId) => ValueKey('unban_$userId');

  @override
  State<BannedMembersView> createState() => _BannedMembersViewState();
}

class _BannedMembersViewState extends State<BannedMembersView> {
  late final list = BannedMembersList(widget.moderation);
  bool loading = true;
  String? error;
  String? unbanning;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      await list.refresh();
      error = null;
    } catch (e, s) {
      Log.onError(e, s, content: "Could not list banned members");
      error = ModerationStrings.errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> unban(BannedMember member) async {
    final answer = await ModerationReasonDialog.ask(context,
        title: BannedMembersView.promptUnban,
        prompt: BannedMembersView.messageUnbanConfirmation(
            member.displayName ?? member.userId),
        confirmText: BannedMembersView.promptUnban);
    if (answer == null || !mounted) return;
    setState(() {
      unbanning = member.userId;
      error = null;
    });
    try {
      await list.unban(member.userId, reason: answer.reason);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not unban a member");
      error = ModerationStrings.errorText(e);
    }
    if (mounted) setState(() => unbanning = null);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        if (error != null) Text(error!, style: TextStyle(color: colors.error)),
        if (list.members.isEmpty && error == null)
          tiamat.Text.labelLow(BannedMembersView.labelNoBannedMembers),
        for (final member in list.members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(member.displayName ?? member.userId,
                overflow: TextOverflow.ellipsis),
            subtitle: member.displayName == null && member.reason == null
                ? null
                : Text([
                    if (member.displayName != null) member.userId,
                    if (member.reason != null)
                      BannedMembersView.labelBanReason(member.reason!),
                  ].join('\n')),
            trailing: widget.moderation.canBan
                ? SizedBox(
                    height: 36,
                    child: tiamat.Button.secondary(
                      key: BannedMembersView.unbanKey(member.userId),
                      text: BannedMembersView.promptUnban,
                      isLoading: unbanning == member.userId,
                      onTap: unbanning == null ? () => unban(member) : null,
                    ),
                  )
                : null,
          ),
      ],
    );
  }
}
