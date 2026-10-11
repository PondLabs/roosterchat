import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';

/// Someone in a call as the surfaces outside the window show them (the
/// in-game overlay, the browser's floating panel): talking, muted or
/// deafened, read from the call's streams.
class CallMember {
  const CallMember(this.userId,
      {this.talking = false, this.muted = false, this.deafened = false});

  final String userId;
  final bool talking;
  final bool muted;
  final bool deafened;

  /// A stream someone's voice is coming through right now. Screen share
  /// audio and the DJ booth's music are not someone talking.
  static bool isTalking(VoipStream stream) =>
      stream.type != VoipStreamType.screenshare &&
      stream.type != VoipStreamType.screenshareAudio &&
      stream.type != VoipStreamType.music &&
      stream.audiolevel > 0.5;

  /// Everyone in [session], ourselves included, in the order they came.
  ///
  /// Someone who publishes nothing (a microphone that would not open) is in
  /// it without being muted. Someone on two devices is muted only when both
  /// are. Our own mute and deafen come from the session, which knows them
  /// before our stream does.
  static List<CallMember> of(VoipSession session) {
    final self = session.client.self?.identifier;
    final ids = <String>{};
    final talking = <String>{};
    final heard = <String>{};
    final silent = <String>{};
    final listening = <String>{};
    final deafened = <String>{};

    for (final stream in session.streams) {
      final id = stream.streamUserId;
      ids.add(id);
      if (isTalking(stream)) talking.add(id);
      if (stream.type != VoipStreamType.audio) continue;
      (stream.isMuted || stream.isDeafened ? silent : heard).add(id);
      (stream.isDeafened ? deafened : listening).add(id);
    }
    if (session case CallRoster roster) ids.addAll(roster.connectedUserIds);

    return [
      for (final id in ids)
        id == self
            ? CallMember(id,
                talking: talking.contains(id),
                muted: session.isMicrophoneMuted || session.isDeafened,
                deafened: session.isDeafened)
            : CallMember(id,
                talking: talking.contains(id),
                muted: silent.contains(id) && !heard.contains(id),
                deafened: deafened.contains(id) && !listening.contains(id)),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is CallMember &&
      other.userId == userId &&
      other.talking == talking &&
      other.muted == muted &&
      other.deafened == deafened;

  @override
  int get hashCode => Object.hash(userId, talking, muted, deafened);

  @override
  String toString() => "CallMember($userId, talking: $talking, "
      "muted: $muted, deafened: $deafened)";
}
