// Shared overlay state: which sender currently has a visible emoji.
//
// Written by the call's SoundboardCallController (from the engine's
// activations), read by every VoipStreamView. Keyed by Matrix userId so the
// emoji appears ONLY on the sender's avatar — never broadcast to all tiles.
// An entry stays until the controller clears it, when the sound's audio ends.
import 'package:rooster/client/components/soundboard/soundboard_emoji.dart';
import 'package:flutter/widgets.dart';

class SoundboardOverlayEntry {
  /// The activation shown: a new trigger is a new entry, even of the same
  /// sound.
  final String eventId;
  final String soundId;
  final SoundboardEmoji emoji;

  /// Image of a custom [emoji], resolved by the caller that has a client.
  final ImageProvider? image;

  const SoundboardOverlayEntry({
    required this.eventId,
    required this.soundId,
    required this.emoji,
    this.image,
  });
}

class SoundboardOverlayRegistry extends ChangeNotifier {
  static final SoundboardOverlayRegistry instance =
      SoundboardOverlayRegistry._();
  SoundboardOverlayRegistry._();

  final Map<String, SoundboardOverlayEntry> _byUser = {};

  SoundboardOverlayEntry? entryFor(String userId) => _byUser[userId];

  /// Shows [entry] on [userId]'s avatar, in place of what was there.
  void show(String userId, SoundboardOverlayEntry entry) {
    _byUser[userId] = entry;
    notifyListeners();
  }

  /// Clears [userId]'s overlay only if it still shows [eventId]: a newer
  /// sound of theirs keeps its own.
  void clearEvent(String userId, String eventId) {
    if (_byUser[userId]?.eventId == eventId) clearUser(userId);
  }

  void clearUser(String userId) {
    if (_byUser.remove(userId) != null) notifyListeners();
  }

  void clearAll() {
    if (_byUser.isNotEmpty) {
      _byUser.clear();
      notifyListeners();
    }
  }

  /// Test seam.
  void clearForTests() => clearAll();
}
