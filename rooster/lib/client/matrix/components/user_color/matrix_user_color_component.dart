import 'dart:async';
import 'dart:ui';

import 'package:matrix/matrix.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/user_color/name_color_cache.dart';
import 'package:rooster/client/components/user_color/user_color_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/utils/color_utils.dart';
import 'package:tiamat/config/style/theme_changer.dart';

class MatrixUserColorComponent
    implements UserColorComponent<MatrixClient>, NeedsPostLoginInit {
  static const String key = "im.vector.setting.override_colors";

  @override
  MatrixClient client;

  late final NameColorCache publicColors = NameColorCache((userId) async {
    try {
      return (await client.matrixClient
          .getProfileField(userId, NameColorCache.key))[NameColorCache.key];
    } on MatrixException catch (e) {
      // Not set, not ours to see, or a homeserver without profile fields.
      if (e.error == MatrixError.M_NOT_FOUND ||
          e.error == MatrixError.M_FORBIDDEN ||
          e.error == MatrixError.M_UNRECOGNIZED) {
        return null;
      }
      rethrow;
    }
  });

  final StreamController<String> _changed = StreamController.broadcast();

  /// The overrides as last seen, to tell which ones another session changed.
  Map<String, Object?> _seenOverrides = const {};

  MatrixUserColorComponent(this.client) {
    publicColors.onChanged.listen(_changed.add);
    client.matrixClient.onSync.stream.listen(_onSync);

    // Names on screen may have been drawn with the other theme's variant.
    // Themes change rarely, so every change repaints them.
    ThemeChanger.onThemeChanged.stream
        .listen((_) => publicColors.coloredIds.toList().forEach(_changed.add));
  }

  @override
  Stream<String> get onColorChanged => _changed.stream;

  @override
  Color? getColor(String identifier) =>
      getOverride(identifier) ??
      publicColors.get(identifier)?.forBrightness(ThemeChanger.brightness);

  @override
  Color? getOverride(String identifier) {
    final override = client.matrixClient.accountData[key]?.content[identifier];
    return override is String ? ColorUtils.fromHexCode(override) : null;
  }

  @override
  Future<void> setColor(String identifier, Color? color) async {
    final overrides = Map<String, Object?>.from(
        client.matrixClient.accountData[key]?.content ?? const {});

    if (color == null) {
      overrides.remove(identifier);
    } else {
      overrides[identifier] = color.toHexCode();
    }

    await client.matrixClient
        .setAccountData(client.matrixClient.userID!, key, overrides);

    // What sync will bring back, so the new color draws now.
    client.matrixClient.accountData[key] =
        BasicEvent(type: key, content: overrides);
    _seenOverrides = overrides;
    _changed.add(identifier);
  }

  void _onSync(SyncUpdate sync) {
    final event = sync.accountData?.where((e) => e.type == key).lastOrNull;
    if (event == null) return;

    final overrides = Map<String, Object?>.from(event.content);
    for (final id in {..._seenOverrides.keys, ...overrides.keys}) {
      if (_seenOverrides[id] != overrides[id]) _changed.add(id);
    }
    _seenOverrides = overrides;
  }

  @override
  void requestPublicColor(String identifier) =>
      publicColors.request(identifier);

  @override
  Future<NameColor?> getOwnPublicColor() async {
    final me = client.matrixClient.userID!;
    Object? value;
    try {
      value = (await client.matrixClient
          .getProfileField(me, NameColorCache.key))[NameColorCache.key];
    } on MatrixException catch (e) {
      if (e.error != MatrixError.M_NOT_FOUND) rethrow;
    }

    final color = NameColorCache.parse(value);
    publicColors.set(me, color);
    return color;
  }

  @override
  Future<void> setOwnPublicColor(NameColor? color) async {
    final me = client.matrixClient.userID!;
    if (color == null) {
      try {
        await client.matrixClient.deleteProfileField(me, NameColorCache.key);
      } on MatrixException catch (e) {
        if (e.error != MatrixError.M_NOT_FOUND) rethrow;
      }
    } else {
      await client.matrixClient.setProfileField(me, NameColorCache.key,
          {NameColorCache.key: NameColorCache.serialize(color)});
    }

    publicColors.set(me, color);
  }

  @override
  void postLoginInit() {
    _seenOverrides = Map<String, Object?>.from(
        client.matrixClient.accountData[key]?.content ?? const {});
  }
}
