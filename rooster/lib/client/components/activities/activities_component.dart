import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/widgets/widget_component.dart';
import 'package:rooster/utils/image_or_icon.dart';

/// Media a participant is publishing that the room list shows (issue #9).
enum LiveMedia { screen, camera }

/// How a voice channel member has silenced themselves, shown next to their
/// name in the room list. [deafened] implies [muted]: deafening turns the
/// microphone off too.
enum VoiceState { muted, deafened }

/// A call activity (a game) someone in the call is in, shown next to their
/// name in the room list.
class ActivityBadge {
  const ActivityBadge(
      {required this.name, required this.icon, this.watching = false});

  final String name;
  final ImageOrIcon icon;

  /// A spectator, not a player.
  final bool watching;
}

class RoomActivitySession {
  Set<String> participants;

  /// What each participant is publishing, for those who reported it or are
  /// in our own call. Participants without an entry publish nothing we know
  /// of.
  final Map<String, Set<LiveMedia>> liveMedia = {};

  /// Who has muted or deafened themselves, for those who reported it or are
  /// in our own call. Participants without an entry are on a client that
  /// does not report it, and get no indicator rather than a wrong one.
  final Map<String, Set<VoiceState>> voiceState = {};

  /// Who is the DJ in the call's booth, by their membership, and whether
  /// their music is playing. For people outside the call, who don't get the
  /// booth's own messages; inside it the booth itself is shown.
  final Map<String, bool> djPlaying = {};

  /// Who is in a call activity, by user id: its host, and in our own call
  /// its players and spectators too.
  final Map<String, ActivityBadge> playing = {};

  String application;

  bool thirdparty;

  /// The voice call itself, not an activity running in or beside it.
  bool get isCall => application == "m.call";

  ImageOrIcon icon;

  String? knownName;
  String get name => knownName ?? application;

  UserWidgetInfo? associatedWidget;

  RoomActivitySession(
      {required this.participants,
      required this.application,
      this.thirdparty = true,
      required this.icon,
      this.associatedWidget,
      String? appName}) {
    this.knownName = appName;
  }
}

abstract class ActivitiesComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  List<RoomActivitySession> getSessions();

  Stream<void> get onSessionsChanged;

  Future<void> clearMemberships(RoomActivitySession session);
}
