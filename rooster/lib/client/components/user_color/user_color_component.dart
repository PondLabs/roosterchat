import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';
import 'package:flutter/widgets.dart';

/// A name color someone picked for themselves (MSC4522): one for dark themes,
/// one for light themes.
class NameColor {
  const NameColor({required this.onDark, required this.onLight});
  final Color onDark;
  final Color onLight;

  Color forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? onDark : onLight;

  @override
  bool operator ==(Object other) =>
      other is NameColor && other.onDark == onDark && other.onLight == onLight;

  @override
  int get hashCode => Object.hash(onDark, onLight);
}

abstract class UserColorComponent<T extends Client> implements Component<T> {
  /// Local override if we set one, else their public color if already known
  /// (for the app's current brightness), else null. Never fetches.
  Color? getColor(String identifier);

  /// The local override only (the color only we see).
  Color? getOverride(String identifier);

  /// Sets or clears (null) the local override. Emits [onColorChanged].
  Future<void> setColor(String identifier, Color? color);

  /// Fetches their public color if unknown or stale. Emits [onColorChanged]
  /// when it arrives and differs from what we had.
  void requestPublicColor(String identifier);

  /// Our own public color, fresh from the server. null = automatic.
  Future<NameColor?> getOwnPublicColor();

  /// Sets (or removes, with null) our own public color. Updates the cache and
  /// emits.
  Future<void> setOwnPublicColor(NameColor? color);

  /// The id of a user whose drawn color may have changed (override or public).
  Stream<String> get onColorChanged;
}
