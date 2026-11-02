import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/direct_messages/direct_message_component.dart';
import 'package:rooster/client/components/invitation/invitation_component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/ui/atoms/scaled_safe_area.dart';
import 'package:rooster/ui/molecules/profile/mini_profile_view.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/debounce.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class SendInvitationWidget extends StatefulWidget {
  const SendInvitationWidget(this.client, this.component,
      {super.key,
      this.roomId,
      this.displayName,
      this.onUserPicked,
      this.showSuggestions = true,
      this.existingMembers});
  final Client client;
  final bool showSuggestions;
  final Iterable<String>? existingMembers;

  final Future<void> Function(String userId)? onUserPicked;

  final String? roomId;
  final String? displayName;
  final InvitationComponent component;

  @override
  State<SendInvitationWidget> createState() => _SendInvitationWidgetState();
}

class _SendInvitationWidgetState extends State<SendInvitationWidget> {
  late TextEditingController controller;
  late Debouncer debouncer;

  bool isSearching = false;
  List<Profile>? searchResults;

  bool loading = false;

  String get messageRoomInviteNoUsers => Intl.message(
      "Could not find any users",
      name: "messageRoomInviteNoUsers",
      desc:
          "In the dialog that invites people to a room, when searching found nobody; a button under it still sends the invite to what was typed");

  String get promptRoomInviteSend => Intl.message("Send invite",
      name: "promptRoomInviteSend",
      desc:
          "Button in the invite dialog that invites the Matrix ID typed in the search field, when searching found nobody");

  String get labelRoomInviteRecommended => Intl.message("Recommended",
      name: "labelRoomInviteRecommended",
      desc:
          "Header in the invite dialog over the people we have direct messages with, suggested to invite");

  String promptRoomInviteConfirm(String userId, String roomName) => Intl.message(
      "Are you sure you want to invite $userId to the room $roomName?",
      name: "promptRoomInviteConfirm",
      args: [userId, roomName],
      desc:
          "Confirmation before inviting someone (their Matrix ID) to a room (its name)");

  String get labelRoomInviteConfirmTitle => Intl.message("Invitation",
      name: "labelRoomInviteConfirmTitle",
      desc: "Title of the confirmation before inviting someone to a room");

  bool get showRecommendations =>
      (!(isSearching || searchResults?.isNotEmpty == true)) &&
      widget.showSuggestions;

  @override
  void initState() {
    controller = TextEditingController();
    debouncer = Debouncer(delay: const Duration(milliseconds: 500));
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var dmComponent = widget.client.getComponent<DirectMessagesComponent>();
    var recommended = List.from(dmComponent?.directMessageRooms ?? []);

    recommended.removeWhere((element) =>
        widget.existingMembers
            ?.contains(dmComponent?.getDirectMessagePartnerId(element)) ==
        true);

    return Opacity(
      opacity: loading ? 0.3 : 1.0,
      child: IgnorePointer(
        ignoring: loading,
        child: ScaledSafeArea(
          child: SizedBox(
              width: 500,
              child: Column(children: [
                tiamat.TextInput(
                  controller: controller,
                  icon: const Icon(Icons.search),
                  maxLines: 1,
                  onChanged: onSearchTextChanged,
                ),
                if (isSearching || searchResults?.isNotEmpty == true)
                  SizedBox(
                      height: 300,
                      child: isSearching
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              itemCount: searchResults!.length,
                              shrinkWrap: true,
                              itemBuilder: (context, index) {
                                return MiniProfileView(
                                  client: widget.component.client,
                                  userId: searchResults![index].identifier,
                                  initialProfile: searchResults![index],
                                  onTap: () => invitePeer(
                                      searchResults![index].identifier),
                                );
                              },
                            )),
                if (!isSearching && searchResults?.isEmpty == true)
                  Column(
                    children: [
                      tiamat.Text(messageRoomInviteNoUsers),
                      tiamat.Button(
                        text: promptRoomInviteSend,
                        onTap: () => invitePeer(controller.text),
                      )
                    ],
                  ),
                if (showRecommendations && recommended.isNotEmpty)
                  Column(
                    children: [
                      const tiamat.Seperator(),
                      tiamat.Text.labelLow(labelRoomInviteRecommended),
                      ListView.builder(
                        shrinkWrap: true,
                        itemCount: recommended.length,
                        itemBuilder: (context, index) {
                          var room = recommended[index];
                          var userId =
                              dmComponent!.getDirectMessagePartnerId(room)!;
                          return MiniProfileView(
                              client: room.client,
                              onTap: () => invitePeer(userId),
                              userId: userId);
                        },
                      ),
                    ],
                  )
              ])),
        ),
      ),
    );
  }

  void onSearchTextChanged(String value) async {
    setState(() {
      isSearching = value.isNotEmpty;
      searchResults = null;
      debouncer.cancel();
    });

    if (value.isNotEmpty) {
      debouncer.run(() => doSearch(value));
    }
  }

  void doSearch(String value) async {
    var result = await widget.component.searchUsers(value);

    setState(() {
      isSearching = false;
      searchResults = result;
    });
  }

  void invitePeer(String userId) async {
    setState(() {
      loading = true;
    });

    if (widget.onUserPicked != null) {
      await widget.onUserPicked?.call(userId);

      if (mounted) Navigator.pop(context);
      return;
    }

    final confirm = await AdaptiveDialog.confirmation(context,
        prompt: promptRoomInviteConfirm(userId, widget.displayName ?? ""),
        title: labelRoomInviteConfirmTitle);
    if (confirm != true) {
      return;
    }

    widget.component.inviteUserToRoom(userId: userId, roomId: widget.roomId!);

    if (mounted) Navigator.pop(context);
  }
}
