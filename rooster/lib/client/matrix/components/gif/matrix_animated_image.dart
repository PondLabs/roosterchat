/// Whether an image or sticker is animated, from its `info`: the
/// `is_animated` of Matrix v1.18 (MSC4230), and the `chat.commet.animated`
/// Rooster wrote before it, which older Rooster clients still read.
abstract class AnimatedImageInfo {
  static const key = "is_animated";
  static const legacyKey = "chat.commet.animated";

  /// What the sender said: `is_animated` when it is a boolean, true for the
  /// legacy key, null when neither says.
  static bool? declared(Map<String, Object?>? info) {
    final stable = info?[key];
    if (stable is bool) return stable;
    if (info?[legacyKey] == true) return true;
    return null;
  }

  /// Whether to treat the image as animated: what the sender declared, or
  /// otherwise a GIF by its [mimetype].
  static bool isAnimated(Map<String, Object?>? info, {String? mimetype}) =>
      declared(info) ?? mimetype?.toLowerCase() == "image/gif";

  /// [info] marked animated with both keys.
  static Map<String, Object?> markAnimated(Map<String, Object?>? info) => {
        ...?info,
        key: true,
        legacyKey: true,
      };
}
