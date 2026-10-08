import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/activities/activities_component.dart';
import 'package:rooster/client/components/direct_messages/direct_message_component.dart';
import 'package:rooster/client/components/invitation/invitation_component.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/invitation_view/send_invitation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Bringing people into a channel, from its row in the sidebar: invited
/// into the room (and its space), or, for a voice channel we are in, sent a
/// direct message with a link to come over. See docs/channel-categories.md.
class ChannelInvites {
  static String get promptInvitePeople => Intl.message("Invite people",
      name: "promptInvitePeople",
      desc: "Button on a channel in the sidebar that invites someone into "
          "it");

  static String get labelInviteToVoice => Intl.message("Invite to voice",
      name: "labelInviteToVoice",
      desc: "Row under a voice channel we are in, which lists people to "
          "call over");

  static String get promptSeeMoreInvitees => Intl.message("See more…",
      name: "promptSeeMoreInvitees",
      desc: "Last entry of the short list of people to invite to a voice "
          "channel; opens all of them");

  static String get labelEveryoneIsHere =>
      Intl.message("Everyone's already here.",
          name: "labelEveryoneIsHere",
          desc: "Shown instead of the people to invite to a voice channel when "
              "there is nobody left to invite");

  static String get promptSendVoiceInvite => Intl.message("Invite",
      name: "promptSendVoiceInvite",
      desc: "Button next to someone in the list of people to invite to a "
          "voice channel");

  static String get labelVoiceInviteSent => Intl.message("Invited",
      name: "labelVoiceInviteSent",
      desc: "Next to someone already sent an invite to a voice channel");

  static String get errorVoiceInvite =>
      Intl.message("Could not send the invite, try again",
          name: "errorVoiceInvite",
          desc: "Next to someone the invite to a voice channel failed for");

  static String get labelSearchPeople => Intl.message("Search",
      name: "labelSearchPeople",
      desc: "Placeholder of the field filtering the people to invite to a "
          "voice channel");

  static String messageVoiceInvite(String channel, String link) =>
      Intl.message("Come hang out in 🔊 $channel: $link",
          name: "messageVoiceInvite",
          args: [channel, link],
          desc: "Direct message sent to someone invited to a voice channel, "
              "with the link that opens it");

  /// Who [userId]s an invite has gone to, per voice channel, while the app
  /// runs: one press each, not one per opening of the list.
  static final Set<String> _sent = {};

  static String _sentKey(Room room, String userId) => "${room.localId}/$userId";

  static bool wasInvited(Room room, String userId) =>
      _sent.contains(_sentKey(room, userId));

  /// Everyone in [room]'s call right now.
  static Set<String> callParticipants(Room room) => {
        for (final session
            in room.getComponent<ActivitiesComponent>()?.getSessions() ??
                const <RoomActivitySession>[])
          if (!session.thirdparty) ...session.participants,
      };

  /// Opens the invite dialog for [room]. Who is picked is invited to the
  /// room, and to [space] too, which they may not be in yet.
  static Future<void> inviteToChannel(BuildContext context, Room room,
      {Space? space}) async {
    final invitation = room.client.getComponent<InvitationComponent>();
    if (invitation == null) return;

    await AdaptiveDialog.show(context,
        title: promptInvitePeople,
        builder: (dialogContext) => SendInvitationWidget(
              room.client,
              invitation,
              roomId: room.identifier,
              displayName: room.displayName,
              existingMembers: room.memberIds,
              onUserPicked: (userId) async {
                if (space != null && space.permissions.canInviteUser) {
                  try {
                    await invitation.inviteUserToRoom(
                        userId: userId, roomId: space.identifier);
                  } catch (e, s) {
                    // Most likely in it already.
                    Log.onError(e, s,
                        content: "Could not invite $userId to the space");
                  }
                }
                try {
                  await invitation.inviteUserToRoom(
                      userId: userId, roomId: room.identifier);
                } catch (e, s) {
                  Log.onError(e, s, content: "Could not invite $userId");
                  if (context.mounted) {
                    AdaptiveDialog.showError(context, e, s,
                        title: promptInvitePeople);
                  }
                }
              },
            ));
  }

  /// Sends [userId] a direct message with a link to the voice channel
  /// [room], opening one with them first if there is none.
  static Future<void> sendVoiceInvite(Room room, String userId) async {
    final dms = room.client.getComponent<DirectMessagesComponent>();
    if (dms == null) throw StateError("No direct messages on this account");

    final link = await room.getShareLink();
    final dm = await dms.createDirectMessage(userId);
    if (dm == null) throw StateError("No direct message with $userId");

    await dm.sendMessage(
        message: messageVoiceInvite(room.displayName, link.toString()));
    _sent.add(_sentKey(room, userId));
  }

  /// Who can be invited to [room]'s call: the people of the channel and of
  /// [space] who are not in it, ourselves aside, by name.
  static Future<List<Member>> voiceInviteCandidates(Room room,
      {Space? space}) async {
    final lists = await Future.wait([
      room.fetchMembersList(cache: true),
      if (space != null) space.fetchMembers(),
    ]);

    final excluded = {
      ...callParticipants(room),
      if (room.client.self != null) room.client.self!.identifier,
    };
    final byId = <String, Member>{};
    for (final list in lists) {
      for (final member in list) {
        if (excluded.contains(member.identifier)) continue;
        byId.putIfAbsent(member.identifier, () => member);
      }
    }

    return byId.values.toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  }

  /// Everyone who can be invited to [room]'s call, searchable.
  static Future<void> showVoiceInviteDialog(BuildContext context, Room room,
      {Space? space}) {
    return AdaptiveDialog.show(context,
        title: labelInviteToVoice,
        scrollable: false,
        builder: (context) => SizedBox(
              width: 360,
              height: 420,
              child: VoiceInviteList(room: room, space: space, search: true),
            ));
  }
}

/// People to invite to a voice channel's call, each with a button that
/// sends them the link. Short ([limit]) in the popover under the channel,
/// with "See more…" opening [onSeeMore]; whole and searchable in the dialog.
class VoiceInviteList extends StatefulWidget {
  const VoiceInviteList({
    required this.room,
    this.space,
    this.limit,
    this.onSeeMore,
    this.search = false,
    super.key,
  });

  final Room room;
  final Space? space;
  final int? limit;
  final VoidCallback? onSeeMore;
  final bool search;

  @override
  State<VoiceInviteList> createState() => _VoiceInviteListState();
}

enum _InviteState { sending, sent, failed }

class _VoiceInviteListState extends State<VoiceInviteList> {
  late final Future<List<Member>> candidates =
      ChannelInvites.voiceInviteCandidates(widget.room, space: widget.space);

  final Map<String, _InviteState> states = {};
  String filter = "";

  _InviteState? stateOf(String userId) =>
      states[userId] ??
      (ChannelInvites.wasInvited(widget.room, userId)
          ? _InviteState.sent
          : null);

  Future<void> invite(Member member) async {
    setState(() => states[member.identifier] = _InviteState.sending);
    try {
      await ChannelInvites.sendVoiceInvite(widget.room, member.identifier);
      if (mounted)
        setState(() => states[member.identifier] = _InviteState.sent);
    } catch (e, s) {
      Log.onError(e, s,
          content: "Could not invite ${member.identifier} to voice");
      if (mounted) {
        setState(() => states[member.identifier] = _InviteState.failed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Member>>(
      future: candidates,
      builder: (context, snapshot) {
        final members = snapshot.data;
        if (members == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: SizedBox.square(
                    dimension: 24, child: CircularProgressIndicator())),
          );
        }

        final query = filter.trim().toLowerCase();
        final matching = query.isEmpty
            ? members
            : members
                .where((m) =>
                    m.displayName.toLowerCase().contains(query) ||
                    m.identifier.toLowerCase().contains(query))
                .toList();
        final limit = widget.limit;
        final shown = limit == null ? matching : matching.take(limit).toList();
        final more = limit != null && matching.length > limit;

        final list = members.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: tiamat.Text.labelLow(ChannelInvites.labelEveryoneIsHere),
              )
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final member in shown) buildMember(member),
                  if (more) buildSeeMore(),
                ],
              );

        if (!widget.search) return list;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: tiamat.TextInput(
                placeholder: ChannelInvites.labelSearchPeople,
                icon: const Icon(Icons.search),
                maxLines: 1,
                onChanged: (value) => setState(() => filter = value),
              ),
            ),
            Expanded(child: list),
          ],
        );
      },
    );
  }

  Widget buildMember(Member member) {
    final colors = Theme.of(context).colorScheme;
    final state = stateOf(member.identifier);

    final Widget action = switch (state) {
      _InviteState.sending => const Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox.square(
              dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      _InviteState.sent => Tooltip(
          message: ChannelInvites.labelVoiceInviteSent,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.check_rounded, size: 20, color: colors.primary),
          ),
        ),
      _ => IconButton(
          tooltip: state == _InviteState.failed
              ? ChannelInvites.errorVoiceInvite
              : ChannelInvites.promptSendVoiceInvite,
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: state == _InviteState.failed ? colors.error : colors.secondary,
          icon: Icon(state == _InviteState.failed
              ? Icons.refresh_rounded
              : Icons.person_add_alt_1_rounded),
          onPressed: () => invite(member),
        ),
    };

    return SizedBox(
      height: 40,
      child: tiamat.TextButton(
        member.displayName,
        avatar: member.avatar,
        avatarPlaceholderColor: member.defaultColor,
        avatarPlaceholderText: member.displayName,
        textColor: colors.onSurface,
        footer: action,
        onTap: state == null || state == _InviteState.failed
            ? () => invite(member)
            : null,
      ),
    );
  }

  Widget buildSeeMore() {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: tiamat.TextButton(
        ChannelInvites.promptSeeMoreInvitees,
        icon: Icons.group_outlined,
        iconColor: colors.secondary,
        textColor: colors.secondary,
        onTap: widget.onSeeMore,
      ),
    );
  }
}
