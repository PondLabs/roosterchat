import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/shortcuts_manager.dart';

/// A circle-masked avatar: [image], or [name]'s initial on [color].
typedef AvatarDrawer = Future<ui.Image> Function(
    {required Color color, required String name, ImageProvider? image});

/// Someone's name and avatar, as far as they have loaded.
class CallFace {
  String? name;

  /// Circle-masked, with their initial when they have no picture.
  ui.Image? avatar;

  bool _loading = false;

  /// When a failed load may be tried again; asked five times a second, it
  /// would otherwise hammer the homeserver.
  DateTime? _retryAfter;
}

/// The names and avatars of the people in calls, for the surfaces outside
/// the window that draw them without widgets: the in-game overlay and the
/// browser's floating panel. Each person is fetched once.
class CallFaces {
  CallFaces({AvatarDrawer? drawAvatar}) : _drawAvatar = drawAvatar ?? _draw;

  final AvatarDrawer _drawAvatar;
  final Map<String, CallFace> _faces = {};

  /// [userId] in [session]'s room, as far as they have loaded. Asking starts
  /// loading them; ask again later for the rest.
  CallFace of(VoipSession session, String userId) {
    final room = session.client.getRoom(session.roomId);
    final face = _faces.putIfAbsent(userId, CallFace.new);
    face.name ??= room?.getMemberOrFallback(userId).displayName;
    final retryAfter = face._retryAfter;
    if (!face._loading &&
        room != null &&
        (retryAfter == null || DateTime.now().isAfter(retryAfter))) {
      face._loading = true;
      _load(face, room, userId).then((_) {
        face._retryAfter = null;
      }, onError: (Object e) {
        // Not loaded yet (a network blip, a slow homeserver): try again.
        Log.w("Could not load $userId for the call: $e");
        face._loading = false;
        face._retryAfter = DateTime.now().add(const Duration(seconds: 30));
      });
    }
    return face;
  }

  /// [Room.getMemberOrFallback] only knows who is loaded, so a name can be
  /// an id until this has fetched them.
  Future<void> _load(CallFace face, Room room, String userId) async {
    final member = await room.fetchMember(userId);
    face.name = member.displayName;
    face.avatar = await avatar(
        color: member.defaultColor,
        name: member.displayName,
        image: member.avatar);
  }

  /// [image] circle-masked, or [name]'s initial when it does not load; null
  /// when even that cannot be drawn.
  Future<ui.Image?> avatar(
      {required Color color,
      required String name,
      ImageProvider? image}) async {
    final initial = name.isEmpty ? "?" : name;
    if (image != null) {
      try {
        return await _drawAvatar(color: color, name: initial, image: image)
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        Log.w("Could not load an avatar for the call: $e");
      }
    }
    try {
      return await _drawAvatar(color: color, name: initial);
    } catch (e) {
      Log.w("Could not draw an avatar for the call: $e");
      return null;
    }
  }

  static Future<ui.Image> _draw(
          {required Color color, required String name, ImageProvider? image}) =>
      ShortcutsManager.createAvatarImage(
          placeholderColor: color,
          placeholderText: name,
          imageProvider: image,
          shouldZoomOut: false);
}
