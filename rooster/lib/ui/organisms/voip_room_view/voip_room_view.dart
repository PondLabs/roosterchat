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
import 'package:tiamat/tiamat.dart' as tiamat;

class VoipRoomView extends StatefulWidget {
  final VoipRoomComponent voip;
  const VoipRoomView(this.voip, {super.key});

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
                ? "This room is encrypted, your call is secure and private"
                : "This room is not encrypted, your call may be accessible by the server operator",
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
                              "It's quiet in here. Pull up a chair.")))),
            ),
          ),
        if (!supportsMediaCapture)
          const Center(
              child: tiamat.Text.labelLow(
                  "Voice needs a secure page: open Rooster over HTTPS to join"))
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
              child: tiamat.Text.labelLow(
                  "You do not have permission to join this call"))
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
                          if (media.isNotEmpty) LiveMediaIndicator(media),
                        ],
                      ),
                    ),
                ],
              ),
              // No room for the name: who is live still shows.
              if (!showName && media.isNotEmpty)
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
          title: "Could not join the call",
          prompt: e.toString(),
          confirmationText: "Retry",
          cancelText: "Close");
      if (retry == true && mounted && !joining) {
        joinRoomCall(withoutEntranceSound: withoutEntranceSound);
      }
    }
  }

  e2eeUnsupportedView() {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: tiamat.Text.label(
          "Sorry, End-to-end encrypted voice rooms are not yet supported."),
    ));
  }
}
