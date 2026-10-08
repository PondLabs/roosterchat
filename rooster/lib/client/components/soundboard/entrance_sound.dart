// Entrance sound: a soundboard sound played once when the user joins a
// voice channel (Discord's "Entrance sounds").
import 'dart:async';

import 'package:rooster/client/components/soundboard/soundboard_catalog.dart';
import 'package:rooster/client/components/soundboard/soundboard_sound.dart';
import 'package:rooster/client/components/voip/voip_session.dart';

/// The user's saved choice. [soundId] null = "None"; [spaceId] null = every
/// Space, otherwise only rooms of that Space.
class EntranceSoundChoice {
  final SoundId? soundId;
  final String? spaceId;

  const EntranceSoundChoice({this.soundId, this.spaceId});
}

/// Which sound to trigger on join, or null to play nothing. [roomSpaceIds]
/// are the Spaces the voice room belongs to (it can be in several); a choice
/// scoped to one Space plays when the room is in it.
SoundId? pickEntranceSound({
  required EntranceSoundChoice choice,
  required Iterable<String> roomSpaceIds,
  required SoundboardCatalog catalog,
  required bool deafened,
}) {
  final soundId = choice.soundId;
  if (soundId == null || deafened) return null;
  if (choice.spaceId != null && !roomSpaceIds.contains(choice.spaceId)) {
    return null;
  }
  // Sound ids are per-Space; one from another Space's catalog can't play here.
  if (catalog.getById(soundId) == null) return null;
  return soundId;
}

/// The entrance sound to trigger now that [session] has started, or null.
/// Voice channels only ([isVoiceChannel], not 1:1 calls), once per session
/// ([gate]), and only for a connected session that isn't deafened. The
/// deafen and mute toggles outside a call only play a feedback sound, so the
/// session's own state is the only one that counts.
SoundId? claimEntranceSound({
  required VoipSession session,
  required bool isVoiceChannel,
  required EntranceSoundChoice choice,
  required Iterable<String> roomSpaceIds,
  required SoundboardCatalog catalog,
  EntranceSoundGate? gate,
}) {
  if (!isVoiceChannel) return null;
  if (session.state != VoipState.connected) return null;
  gate ??= EntranceSoundGate.instance;
  if (!gate.claim(session, roomId: session.roomId)) return null;
  return pickEntranceSound(
    choice: choice,
    roomSpaceIds: roomSpaceIds,
    catalog: catalog,
    deafened: session.isDeafened,
  );
}

/// Makes the entrance sound fire at most once per call session, and carries
/// join requests (with the entrance sound or without) to the voice view. The call view
/// (and its soundboard controller) is rebuilt whenever the user navigates back
/// to the room, so the controller alone can't tell a join from a revisit.
class EntranceSoundGate {
  static final EntranceSoundGate instance = EntranceSoundGate();

  /// How long a join request waits for its room's view to open. Older
  /// requests are dropped so a later visit doesn't join.
  static const Duration silentJoinRequestTtl = Duration(seconds: 10);

  final DateTime Function() _now;
  final Expando<bool> _claimed = Expando('entranceSoundClaimed');
  final Set<String> _skipRooms = {};

  /// Join requests by room: when, and whether without the entrance sound.
  final Map<String, (DateTime, bool)> _joinRequests = {};
  final StreamController<String> _onJoinRequested =
      StreamController.broadcast();

  EntranceSoundGate({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Room ids with a new join request, for views that are already open.
  Stream<String> get onJoinRequested => _onJoinRequested.stream;

  /// Asks the voice view of [roomId] to join, with the entrance sound unless
  /// [silent]: the rail under the spaces opens a channel and joins it in one
  /// go, the way "Join Without Entrance Sound" does without the sound.
  void requestJoin(String roomId, {bool silent = false}) {
    _joinRequests[roomId] = (_now(), silent);
    _onJoinRequested.add(roomId);
  }

  /// Asks the voice view of [roomId] to join without the entrance sound.
  void requestSilentJoin(String roomId) => requestJoin(roomId, silent: true);

  /// Takes the fresh join request for [roomId], once: whether it asked for
  /// no entrance sound, or null with none.
  bool? takeJoinRequest(String roomId) {
    final request = _joinRequests.remove(roomId);
    if (request == null) return null;
    final (requestedAt, silent) = request;
    if (_now().difference(requestedAt) > silentJoinRequestTtl) return null;
    return silent;
  }

  /// True once per fresh [requestSilentJoin] for [roomId].
  bool takeSilentJoinRequest(String roomId) => takeJoinRequest(roomId) == true;

  /// The next join of [roomId] plays no entrance sound.
  void skipNextJoin(String roomId) => _skipRooms.add(roomId);

  /// Undoes [skipNextJoin], e.g. when that join failed.
  void cancelSkip(String roomId) => _skipRooms.remove(roomId);

  /// True the first time it is called for [session], unless the join was
  /// marked with [skipNextJoin] (which this consumes).
  bool claim(Object session, {required String roomId}) {
    if (_claimed[session] == true) return false;
    _claimed[session] = true;
    return !_skipRooms.remove(roomId);
  }
}
