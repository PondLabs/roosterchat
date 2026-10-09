import 'dart:async';

import 'package:collection/collection.dart';
import 'package:rooster/client/components/activities/activities_component.dart';
import 'package:rooster/client/components/soundboard/entrance_sound.dart';
import 'package:rooster/client/components/voip/media_capture_support.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/live_media_indicator.dart';
import 'package:rooster/ui/atoms/shimmer_loading.dart';
import 'package:rooster/ui/atoms/voice_state_indicator.dart';
import 'package:rooster/ui/layout/bento.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/call_view/call.dart';
import 'package:rooster/ui/organisms/dj/vinyl_disc.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class VoipRoomView extends StatefulWidget {
  final VoipRoomComponent voip;
  const VoipRoomView(this.voip, {super.key});

  static String get tooltipCallRoomEncrypted =>
      Intl.message("This room is encrypted, your call is secure and private",
          name: "tooltipCallRoomEncrypted",
          desc: "Tooltip of the closed lock at the bottom of a voice channel's "
              "page, before joining its call");

  static String get tooltipCallRoomNotEncrypted => Intl.message(
      "This room is not encrypted, your call may be accessible by the server "
      "operator",
      name: "tooltipCallRoomNotEncrypted",
      desc: "Tooltip of the open lock at the bottom of a voice channel's "
          "page, before joining its call");

  static String get labelVoiceChannelEmpty =>
      Intl.message("It's quiet in here. Pull up a chair.",
          name: "labelVoiceChannelEmpty",
          desc: "Shown on a voice channel's page while nobody is in its call; "
              "a friendly invitation to join it");

  static String get messageVoiceNeedsSecurePage =>
      Intl.message("Voice needs a secure page: open Rooster over HTTPS to join",
          name: "messageVoiceNeedsSecurePage",
          desc: "Shown on a voice channel's page, in place of the join button, "
              "when the web app was opened over plain HTTP: the browser gives "
              "no microphone there. Rooster is the app's name");

  static String get messageCallJoinNotAllowed =>
      Intl.message("You do not have permission to join this call",
          name: "messageCallJoinNotAllowed",
          desc: "Shown on a voice channel's page, in place of the join button, "
              "when the user may not join its call");

  static String get errorCallJoinFailed =>
      Intl.message("Could not join the call",
          name: "errorCallJoinFailed",
          desc: "Title of the dialog shown when joining a voice channel's call "
              "failed; the dialog says why, and offers to try again");

  static String get messageVoiceE2eeUnsupported => Intl.message(
      "Sorry, End-to-end encrypted voice rooms are not yet supported.",
      name: "messageVoiceE2eeUnsupported",
      desc: "Shown on the page of a voice channel that is end-to-end "
          "encrypted, where calls cannot be joined yet");

  @override
  State<VoipRoomView> createState() => _VoipRoomViewState();
}

class _VoipRoomViewState extends State<VoipRoomView> {
  VoipSession? currentSession;
  String? callServerUrl;
  late List<String> participants;
  bool joining = false;
  late List<StreamSubscription> subs;

  /// What the people in the call say about themselves (live, camera, muted,
  /// deafened, DJ), from the list the sidebar shows them in: someone
  /// deciding whether to join sees it here too, not only who is in.
  ActivitiesComponent? activities;
  RoomActivitySession? call;

  /// Who has had their member asked for, once each (see
  /// RoomTextButton.fetchNewMembers).
  final Set<String> fetchedMembers = {};

  @override
  void initState() {
    currentSession = widget.voip.currentSession;
    participants = widget.voip.getCurrentParticipants();
    activities = widget.voip.room.getComponent<ActivitiesComponent>();
    call = readCall();

    subs = [
      EntranceSoundGate.instance.onJoinRequested
          .where((id) => id == widget.voip.room.identifier)
          .listen((_) => _takeJoinRequest()),
      widget.voip.onParticipantsChanged.listen((_) {
        // when the participant list changes, the resolved focus may change
        updateCallUrl();

        setState(() {
          participants = widget.voip.getCurrentParticipants();
          call = readCall();
        });
        fetchNewMembers();
      }),
      // A mute or a stream starting changes no participant.
      if (activities != null)
        activities!.onSessionsChanged.listen((_) {
          if (mounted) setState(() => call = readCall());
        }),
    ];

    fetchNewMembers();
    updateCallUrl();
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeJoinRequest());
    widget.voip.clearStaleOwnMembership().catchError((e, s) {
      Log.onError(e, s);
    });
    super.initState();
  }

  RoomActivitySession? readCall() =>
      activities?.getSessions().firstWhereOrNull((s) => !s.thirdparty);

  /// Asks for the member of everyone listed for the first time, for their
  /// name: a member the homeserver lazy loads is only its user id until
  /// then.
  void fetchNewMembers() {
    for (final participant in participants) {
      if (!fetchedMembers.add(participant)) continue;
      widget.voip.room.fetchMember(participant).then((_) {
        if (mounted) setState(() {});
      }, onError: (Object e, StackTrace s) {
        Log.onError(e, s, content: "Could not fetch $participant");
      });
    }
  }

  void _takeJoinRequest() {
    if (!mounted) return;
    // Picks up "Join Without Entrance Sound" from the room's context menu
    // and "Join call" from the rail under the spaces, whether this view was
    // already open or opens because of it.
    final silent =
        EntranceSoundGate.instance.takeJoinRequest(widget.voip.room.identifier);
    if (silent == null) return;
    final inCall =
        currentSession != null && currentSession!.state != VoipState.ended;
    if (inCall || joining || !widget.voip.canJoinCall) return;
    joinRoomCall(withoutEntranceSound: silent);
  }

  void updateCallUrl() {
    widget.voip.getCallServerUrl().then((url) {
      if (mounted) print("Call url: ${url}");
      setState(() {
        callServerUrl = url;
      });
    });
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var color = Theme.of(context).colorScheme.surfaceContainer;

    if (currentSession == null) return unjoinedView(color);

    if (currentSession?.state == VoipState.ended) {
      return unjoinedView(color);
    }

    return CallWidget(currentSession!);
  }

  Column unjoinedView(Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: widget.voip.room.isE2EE &&
                  preferences.experimentEnableE2eeElementCall.value == false
              ? e2eeUnsupportedView()
              : joinCallView(),
        ),
        Align(
          alignment: AlignmentGeometry.bottomLeft,
          child: tiamat.Tooltip(
            text: widget.voip.room.isE2EE
                ? VoipRoomView.tooltipCallRoomEncrypted
                : VoipRoomView.tooltipCallRoomNotEncrypted,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.voip.room.isE2EE)
                    Icon(Icons.lock, color: Colors.greenAccent),
                  if (!widget.voip.room.isE2EE)
                    Icon(Icons.lock_open, color: Colors.red),
                  SizedBox(
                    width: 3,
                  ),
                  Shimmer(
                    child: ShimmerLoading(
                        isLoading: callServerUrl == null,
                        child: callServerUrl == null
                            ? Container(
                                height: 16,
                                width: 150,
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: color),
                              )
                            : tiamat.Text.labelLow(callServerUrl!)),
                  ),
                ],
              ),
            ),
          ),
        )
      ],
    );
  }

  Column joinCallView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (participants.isNotEmpty)
          Expanded(
              child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: BentoLayout(participants.map(participantTile).toList()),
          )),
        if (participants.isEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration:
                      BoxDecoration(borderRadius: BorderRadius.circular(8)),
                  child: tiamat.Tile.surfaceContainer(
                      child: Center(
                          child: tiamat.Text.labelLow(
                              VoipRoomView.labelVoiceChannelEmpty)))),
            ),
          ),
        if (!supportsMediaCapture)
          Center(
              child: tiamat.Text.labelLow(
                  VoipRoomView.messageVoiceNeedsSecurePage))
        else if (widget.voip.canJoinCall)
          Center(
            child: tiamat.Button(
              isLoading: joining,
              text: CommonStrings.promptJoin,
              // Shift+click joins without the entrance sound.
              onTap: () => joinRoomCall(
                  withoutEntranceSound:
                      HardwareKeyboard.instance.isShiftPressed),
            ),
          )
        else
          Center(
              child:
                  tiamat.Text.labelLow(VoipRoomView.messageCallJoinNotAllowed))
      ],
    );
  }

  /// Someone in the call, as seen from outside it: their avatar and name,
  /// with what their membership says about them. The tiles of a full call
  /// are small, so the avatar follows the tile and the name gives way first.
  Widget participantTile(String userId) {
    final member = widget.voip.room.getMemberOrFallback(userId);
    final media = call?.liveMedia[userId] ?? const <LiveMedia>{};
    final voice = call?.voiceState[userId] ?? const <VoiceState>{};
    final djPlaying = call?.djPlaying[userId];
    final deafened = voice.contains(VoiceState.deafened);
    final colors = ColorScheme.of(context);

    return Container(
      key: ValueKey("voipRoomView_participant_$userId"),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: tiamat.Tile.low(
        child: LayoutBuilder(builder: (context, constraints) {
          final radius =
              (constraints.biggest.shortestSide * 0.3).clamp(12.0, 50.0);
          final showName = constraints.maxHeight >= radius * 2 + 56 &&
              constraints.maxWidth >= 72;
          // Who is live goes beside the name on a wide tile, else in the
          // corner: beside a name, LIVE (longer in some languages, "AO VIVO")
          // left a small tile's name no room, or ran past its edge.
          final badgeBesideName = showName && constraints.maxWidth >= 160;

          return Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Padding(
                        padding: EdgeInsets.all(radius * 0.16),
                        // Dimmed while silenced, as on the call's own tiles.
                        child: Opacity(
                          opacity: voice.isEmpty ? 1.0 : 0.5,
                          child: tiamat.Avatar(
                              radius: radius,
                              image: member.avatar,
                              placeholderColor: member.defaultColor,
                              placeholderText: member.displayName),
                        ),
                      ),
                      // The record spins while their music plays.
                      if (djPlaying != null)
                        Positioned(
                          left: 0,
                          top: 0,
                          child: VinylDisc(
                              size: (radius * 0.56).clamp(14.0, 28.0),
                              spinning: djPlaying),
                        ),
                      if (voice.isNotEmpty)
                        Container(
                          decoration: BoxDecoration(
                              color: deafened ? colors.error : colors.primary,
                              borderRadius: BorderRadius.circular(8)),
                          padding: EdgeInsets.all(radius >= 32 ? 8 : 4),
                          child: IconTheme.merge(
                            data: IconThemeData(
                                color: deafened
                                    ? colors.onError
                                    : colors.onPrimary),
                            child: VoiceStateIndicator.badge(voice,
                                size: radius >= 32 ? 18 : 12),
                          ),
                        ),
                    ],
                  ),
                  if (showName)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 6,
                        children: [
                          Flexible(
                            child: tiamat.Text.label(member.displayName,
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (media.isNotEmpty && badgeBesideName)
                            LiveMediaIndicator(media),
                        ],
                      ),
                    ),
                ],
              ),
              // No room beside the name: who is live still shows.
              if (!badgeBesideName && media.isNotEmpty)
                Positioned(top: 6, right: 6, child: LiveMediaIndicator(media)),
            ],
          );
        }),
      ),
    );
  }

  joinRoomCall({bool withoutEntranceSound = false}) async {
    // No capture on this origin (an http page): nothing to join with.
    if (!supportsMediaCapture) return;
    final roomId = widget.voip.room.identifier;
    setState(() {
      joining = true;
    });

    // For better UI feedback if program stutters while joining
    await Future.delayed(Duration(milliseconds: 100));

    if (withoutEntranceSound) EntranceSoundGate.instance.skipNextJoin(roomId);

    try {
      final session = await widget.voip.joinCall();
      if (session == null && withoutEntranceSound) {
        EntranceSoundGate.instance.cancelSkip(roomId);
      }

      if (session != null) {
        setState(() {
          currentSession = session;
          joining = false;
        });
      }
    } catch (e, s) {
      Log.onError(e, s);
      if (withoutEntranceSound) EntranceSoundGate.instance.cancelSkip(roomId);

      if (!mounted) return;
      setState(() {
        joining = false;
      });

      final retry = await AdaptiveDialog.confirmation(context,
          title: VoipRoomView.errorCallJoinFailed,
          prompt: e is CallJoinException ? e.message : e.toString(),
          confirmationText: CommonStrings.promptRetry,
          cancelText: CommonStrings.promptClose);
      if (retry == true && mounted && !joining) {
        joinRoomCall(withoutEntranceSound: withoutEntranceSound);
      }
    }
  }

  e2eeUnsupportedView() {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: tiamat.Text.label(VoipRoomView.messageVoiceE2eeUnsupported),
    ));
  }
}
