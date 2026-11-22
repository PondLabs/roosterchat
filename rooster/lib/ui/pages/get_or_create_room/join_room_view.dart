import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/components/knocking/matrix_knocking_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/room_preview.dart';
import 'package:rooster/client/space_child.dart';
import 'package:rooster/ui/atoms/room_preview.dart';
import 'package:rooster/ui/organisms/chat/knock_request_banner.dart';
import 'package:rooster/ui/organisms/chat/room_notice_banner.dart';
import 'package:rooster/utils/debounce.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

class JoinRoomView extends StatefulWidget {
  const JoinRoomView(this.client,
      {required this.asSpace,
      this.onPicked,
      this.initialRoomAddress,
      super.key});
  final Client client;
  final String? initialRoomAddress;
  final bool asSpace;
  final Function(SpaceChild<dynamic>)? onPicked;

  @override
  State<JoinRoomView> createState() => _JoinRoomViewState();
}

class _JoinRoomViewState extends State<JoinRoomView> {
  Debouncer searchDebouncer = Debouncer(delay: Duration(seconds: 2));

  RoomPreview? preview;
  String text = "";
  bool loading = false;
  bool joinLoading = false;
  bool knockLoading = false;
  bool knockSent = false;

  late TextEditingController controller;

  String get promptConfirmRoomJoin => Intl.message(
        "Join Room!",
        name: "promptConfirmRoomJoin",
        desc: "Label for a button which confirms the joining of a room",
      );

  String get promptRoomAddress => Intl.message(
        "Room Address",
        name: "promptRoomAddress",
        desc: "Short label to prompt for the input of a room address",
      );

  String get placeholderRoomAlias => Intl.message(
        "#awesome-room",
        name: "placeholderRoomAlias",
        desc: "Placeholder / Example for a room alias.",
      );

  @override
  void initState() {
    controller = TextEditingController(text: widget.initialRoomAddress);
    if (widget.initialRoomAddress != null) {
      onTextChanged(widget.initialRoomAddress!);
    }
    super.initState();
  }

  @override
  void dispose() {
    searchDebouncer.cancel();
    controller.dispose();
    super.dispose();
  }

  bool _canJoinDirectly(RoomPreview? p) {
    if (p == null) return true;
    if (p.joinRule == 'knock') return false;
    if (p.joinRule == 'knock_restricted') {
      return switch (p.visibility) {
        RoomVisibilityRestricted(spaces: final allowed) => allowed.any(
            (id) => widget.client.hasSpace(id) || widget.client.hasRoom(id)),
        _ => false,
      };
    }
    return true;
  }

  Future<void> _joinRoom() async {
    setState(() {
      joinLoading = true;
    });

    SpaceChild? result;
    if (preview?.type == RoomType.space) {
      result = SpaceChildSpace(await widget.client.joinSpace(text));
    } else {
      result = SpaceChildRoom(await widget.client.joinRoom(text));
    }

    widget.onPicked?.call(result);
  }

  Future<void> _requestToJoin() async {
    final client = widget.client;
    if (client is! MatrixClient) return;

    final reason = await KnockRequestBanner.promptReason(context);
    if (reason == null || !mounted) return;

    final parsed = client.parseAddressToIdAndVia(text);
    final target = parsed?.$1 ?? preview?.roomId ?? text;
    final via = preview?.via.isNotEmpty == true ? preview!.via : parsed?.$2;

    setState(() => knockLoading = true);
    await ErrorUtils.tryRun(context, () async {
      await MatrixKnockingComponent.knockById(
        client.getMatrixClient(),
        target,
        reason: reason,
        via: via,
      );
      knockSent = true;
    });
    if (mounted) setState(() => knockLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final matrixClient =
        widget.client is MatrixClient ? widget.client as MatrixClient : null;
    final canKnock = matrixClient != null && preview?.canKnock == true;
    final canJoin = _canJoinDirectly(preview);
    final pending = knockSent ||
        (matrixClient != null &&
            preview != null &&
            matrixClient
                    .getMatrixClient()
                    .getRoomById(preview!.roomId)
                    ?.membership ==
                matrix.Membership.knock);

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                  label: Text(promptRoomAddress),
                  hint: tiamat.Text.labelLow(placeholderRoomAlias)),
              onChanged: (value) {
                onTextChanged(value);
              },
            ),
            Flexible(
              child: SizedBox(
                  height: 200,
                  child: loading
                      ? Center(child: CircularProgressIndicator())
                      : preview != null
                          ? Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: RoomPreviewView(previewData: preview!),
                            )
                          : Container()),
            ),
          ],
        ),
        if (pending)
          RoomNoticeBanner(
            icon: Icons.hourglass_top,
            message: KnockRequestBanner.messageKnockPending,
          )
        else if (canKnock && !canJoin)
          tiamat.Button(
            text: KnockRequestBanner.promptRequestToJoin,
            isLoading: knockLoading,
            onTap: knockLoading ? null : _requestToJoin,
          )
        else if (canKnock && canJoin)
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              tiamat.Button(
                text: promptConfirmRoomJoin,
                isLoading: joinLoading,
                onTap: _joinRoom,
              ),
              tiamat.Button.secondary(
                text: KnockRequestBanner.promptRequestToJoin,
                isLoading: knockLoading,
                onTap: knockLoading ? null : _requestToJoin,
              ),
            ],
          )
        else
          tiamat.Button(
            text: promptConfirmRoomJoin,
            isLoading: joinLoading,
            onTap: _joinRoom,
          ),
      ],
    );
  }

  void onTextChanged(String value) {
    text = value;

    if (value.isEmpty) {
      setState(() {
        preview = null;
        loading = false;
        knockSent = false;
      });
      searchDebouncer.cancel();
      return;
    }

    setState(() {
      preview = null;
      loading = true;
      knockSent = false;
    });

    searchDebouncer.run(() async {
      var result = await widget.client.getRoomPreview(value);
      if (!mounted) return;
      setState(() {
        preview = result;
        loading = false;
      });
    });
  }
}
