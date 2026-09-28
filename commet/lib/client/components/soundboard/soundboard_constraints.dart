// Centralized limits for Soundboard import/playback.
//
// Rationale:
// - Soundboard = short SFX, not music. 15s cap keeps preload/memory sane
//   (15s stereo 48kHz f32 ~= 5.7MB decoded; 1MB encoded is generous for SFX).
// - 1MB encoded cap protects bandwidth/storage/preload on mobile.
// - Import takes a file of any length (a whole video's audio, say) and
//   decodes a window of at most 1 min of it for the trim editor; only the
//   trimmed clip, re-encoded, has to fit the 15 s / 1 MiB caps.
class SoundboardConstraints {
  /// Longest stored sound, i.e. the longest selection the trim editor allows.
  static const int maxDurationMs = 15000;

  /// Most audio the trim editor shows at once. Longer sources are opened at
  /// a start point the admin picks.
  static const int maxWindowMs = 60000;

  /// Largest file import reads or downloads, before trimming: room for the
  /// audio of a long video.
  static const int maxSourceFileBytes = 200 * 1024 * 1024;

  /// Shortest selection the trim editor allows.
  static const int minDurationMs = 100;

  /// Fade in and out at the cut points, so a cut mid-waveform doesn't click.
  static const int fadeMs = 5;

  /// Longest a sound may play. Sounds are checked against [maxDurationMs]
  /// when imported, but any Space moderator can point a sound at any file.
  static const int maxPlaybackMs = maxDurationMs + 5000;

  /// Largest stored sound file, enforced again at playback.
  static const int maxFileBytes = 1024 * 1024; // 1 MiB

  /// Stored sounds are Opus in Ogg.
  static const String clipMimeType = 'audio/ogg';

  /// Upper bound of the per-sound admin volume (200 %).
  static const double maxSoundVolume = 2.0;

  static double clampSoundVolume(double volume) =>
      volume.clamp(0.0, maxSoundVolume);

  static const int maxNameLength = 64;
  static const int minNameLength = 1;

  static const List<String> allowedMimeTypes = [
    'audio/mpeg',
    'audio/mp3',
    'audio/ogg',
    'audio/vorbis',
    'audio/opus',
    'audio/wav',
    'audio/x-wav',
    'audio/wave',
    'audio/webm',
    'audio/mp4',
    'audio/aac',
    'audio/flac',
    'audio/x-m4a',
  ];

  /// Event TTL: triggers older than this are dropped (reconnect safety).
  static const Duration eventTtl = Duration(milliseconds: 2500);

  /// Max clock skew into the future before an event is considered invalid.
  static const Duration maxFutureSkew = Duration(seconds: 30);

  /// Max entries in dedup LRU (bounded memory).
  static const int maxDedupEntries = 200;

  /// Live playback instances across all sounds; the oldest is dropped
  /// beyond this so rapid triggers can't pile up audio players.
  static const int maxConcurrentInstances = 8;

  /// Max decoded sounds held in session LRU.
  static const int maxCachedSounds = 20;

  /// Visual overlay duration bounds (ms). Real duration is clamped into this.
  static const int minOverlayMs = 1200;
  static const int maxOverlayMs = 3500;
}
