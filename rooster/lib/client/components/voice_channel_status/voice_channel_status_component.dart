import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/room_component.dart';

/// A line of text under a voice channel's name in the sidebar, saying what
/// it is up to ("Movie night", "Ranked"), as on Discord. Everyone sees it;
/// whoever may set it does so while in the call. See
/// docs/channel-categories.md.
abstract class VoiceChannelStatusComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  static const maxLength = 100;

  /// Null when none is set.
  String? get status;

  bool get canSetStatus;

  /// Fires when the status changes, ours or someone else's.
  Stream<void> get onChanged;

  /// Sets the status; null or blank clears it.
  Future<void> setStatus(String? status);
}
