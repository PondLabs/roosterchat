import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rooster/ui/atoms/speaking_indicator.dart';
import 'package:tiamat/config/style/theme_common.dart';

/// A panel's pixels as the runner takes them: premultiplied RGBA
/// (`ImageByteFormat.rawRgba`), which is what UpdateLayeredWindow blends
/// (windows/runner/game_overlay.cpp).
class OverlayImage {
  const OverlayImage(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;
}

/// Someone in the call as the overlay draws them.
@immutable
class OverlayMember {
  const OverlayMember(
      {required this.name,
      this.avatar,
      this.talking = false,
      this.muted = false,
      this.deafened = false});

  final String name;

  /// Circle-masked; a grey circle stands in while it loads.
  final ui.Image? avatar;
  final bool talking;
  final bool muted;
  final bool deafened;

  @override
  bool operator ==(Object other) =>
      other is OverlayMember &&
      other.name == name &&
      identical(other.avatar, avatar) &&
      other.talking == talking &&
      other.muted == muted &&
      other.deafened == deafened;

  @override
  int get hashCode => Object.hash(name, avatar, talking, muted, deafened);
}

/// A message as the overlay shows it.
class OverlayToast {
  OverlayToast(
      {required this.sender, required this.body, this.room, this.avatar});

  final String sender;
  final String body;

  /// The room's name; null for a direct message.
  final String? room;

  /// Circle-masked; a grey circle stands in until it has loaded.
  ui.Image? avatar;
}

/// Dark pills like Discord's overlay: readable over any game, whatever
/// Rooster's own theme is.
abstract final class _Palette {
  static const pill = Color(0xB3000000);
  static const toast = Color(0xE6111214);
  static const name = Color(0xFFFFFFFF);
  static const idleName = Color(0xBFFFFFFF);
  static const body = Color(0xFFDBDEE1);
  static const detail = Color(0xFFB5BAC1);
  static const badge = Color(0xFFF23F43);
  static const placeholder = Color(0xFF4E5058);
}

// The voice panel, in logical pixels.
const _rowHeight = 32.0;
const _rowGap = 4.0;
const _avatarRadius = 12.0;
const _ringGap = 1.5;
const _ringWidth = 2.0;
const _maxNameWidth = 200.0;
const _badgeSize = 16.0;

// The toasts.
const _toastWidth = 320.0;
const _toastPadding = 10.0;
const _toastAvatarRadius = 18.0;
const _toastGap = 6.0;

/// The people in the call, one pill each, lined up on the corner's side
/// ([alignEnd] for the right-hand corners). [more] is a last pill saying how
/// many did not fit.
Future<OverlayImage> drawVoicePanel(List<OverlayMember> members,
    {String? more, required double scale, bool alignEnd = false}) {
  final rows = <({double width, TextPainter text, OverlayMember? member})>[];
  for (final member in members) {
    final text = _text(member.name,
        size: 14,
        weight: FontWeight.w600,
        color: member.talking ? _Palette.name : _Palette.idleName,
        maxWidth: _maxNameWidth);
    final badge = member.muted || member.deafened ? 4 + _badgeSize : 0;
    rows.add((
      width: _rowHeight + 4 + text.width + badge + 12,
      text: text,
      member: member,
    ));
  }
  if (more != null) {
    final text =
        _text(more, size: 13, color: _Palette.detail, maxWidth: _maxNameWidth);
    rows.add((width: text.width + 24, text: text, member: null));
  }

  final width = rows.fold(0.0, (widest, row) => math.max(widest, row.width));
  final height = rows.length * (_rowHeight + _rowGap) - _rowGap;

  return _rasterize(Size(width, height), scale, (canvas) {
    var y = 0.0;
    for (final row in rows) {
      final x = alignEnd ? width - row.width : 0.0;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, row.width, _rowHeight),
              const Radius.circular(_rowHeight / 2)),
          Paint()..color = _Palette.pill);

      final member = row.member;
      final textY = y + (_rowHeight - row.text.height) / 2;
      if (member == null) {
        row.text.paint(canvas, Offset(x + 12, textY));
        y += _rowHeight + _rowGap;
        continue;
      }

      final center = Offset(x + _rowHeight / 2, y + _rowHeight / 2);
      final silent = member.muted || member.deafened;
      // As on the call tiles: someone who cannot be heard is dimmed, and
      // has no ring.
      _drawAvatar(canvas, member.avatar, center, _avatarRadius,
          opacity: silent ? 0.5 : 1);
      if (member.talking && !silent) {
        canvas.drawCircle(
            center,
            _avatarRadius + _ringGap + _ringWidth / 2,
            Paint()
              ..color = SpeakingIndicator.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = _ringWidth);
      }

      final textX = x + _rowHeight + 4;
      row.text.paint(canvas, Offset(textX, textY));
      if (silent) {
        final icon = _icon(
            member.deafened ? Icons.headset_off_rounded : Icons.mic_off_rounded,
            _badgeSize,
            _Palette.badge);
        icon.paint(
            canvas,
            Offset(textX + row.text.width + 4,
                y + (_rowHeight - icon.height) / 2));
        icon.dispose();
      }
      y += _rowHeight + _rowGap;
    }
  }, dispose: [for (final row in rows) row.text]);
}

/// Messages, oldest at the top: who sent it, where, and the start of it.
Future<OverlayImage> drawToasts(List<OverlayToast> toasts,
    {required double scale}) {
  final laid = [for (final toast in toasts) _LaidToast(toast)];
  final height = laid.fold(0.0, (sum, toast) => sum + toast.height) +
      _toastGap * math.max(0, laid.length - 1);

  return _rasterize(Size(_toastWidth, height), scale, (canvas) {
    var y = 0.0;
    for (final toast in laid) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, y, _toastWidth, toast.height),
              const Radius.circular(10)),
          Paint()..color = _Palette.toast);
      _drawAvatar(
          canvas,
          toast.avatar,
          Offset(_toastPadding + _toastAvatarRadius,
              y + _toastPadding + _toastAvatarRadius),
          _toastAvatarRadius);

      var textY = y + _toastPadding;
      toast.sender.paint(canvas, Offset(_LaidToast.textX, textY));
      textY += toast.sender.height;
      final room = toast.room;
      if (room != null) {
        room.paint(canvas, Offset(_LaidToast.textX, textY + 2));
        textY += room.height + 2;
      }
      toast.body.paint(canvas, Offset(_LaidToast.textX, textY + 4));
      y += toast.height + _toastGap;
    }
  }, dispose: [for (final toast in laid) ...toast.painters]);
}

/// A toast's text, laid out to the toast's width.
class _LaidToast {
  _LaidToast(OverlayToast toast)
      : avatar = toast.avatar,
        sender = _text(toast.sender,
            size: 14,
            weight: FontWeight.w700,
            color: _Palette.name,
            maxWidth: textWidth),
        room = toast.room == null
            ? null
            : _text(toast.room!,
                size: 12, color: _Palette.detail, maxWidth: textWidth),
        body = _text(toast.body,
            size: 13, color: _Palette.body, maxWidth: textWidth, maxLines: 2);

  static const textX = _toastPadding + 2 * _toastAvatarRadius + 10;
  static const textWidth = _toastWidth - textX - _toastPadding;

  final ui.Image? avatar;
  final TextPainter sender;
  final TextPainter? room;
  final TextPainter body;

  double get height =>
      2 * _toastPadding +
      math.max(
          2 * _toastAvatarRadius,
          sender.height +
              (room == null ? 0 : room!.height + 2) +
              4 +
              body.height);

  List<TextPainter> get painters => [sender, body, if (room != null) room!];
}

TextPainter _text(String text,
        {required double size,
        required Color color,
        required double maxWidth,
        FontWeight weight = FontWeight.w400,
        int maxLines = 1}) =>
    TextPainter(
      text: TextSpan(
        // One line per name, and a message's line breaks would waste the
        // two lines it has.
        text: text.replaceAll(RegExp(r'\s*\n\s*'), ' '),
        style: TextStyle(
          fontFamily: "Roboto",
          fontFamilyFallback: ThemeCommon.fontFamilyFallback(),
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.25,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: "…", // Not translated: punctuation.
    )..layout(maxWidth: maxWidth);

TextPainter _icon(IconData glyph, double size, Color color) => TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(glyph.codePoint),
        style: TextStyle(
          fontFamily: glyph.fontFamily,
          package: glyph.fontPackage,
          fontSize: size,
          height: 1.0,
          color: color,
        ),
      ),
    )..layout();

void _drawAvatar(Canvas canvas, ui.Image? image, Offset center, double radius,
    {double opacity = 1}) {
  final circle = Rect.fromCircle(center: center, radius: radius);
  if (image == null) {
    canvas.drawCircle(center, radius,
        Paint()..color = _Palette.placeholder.withValues(alpha: opacity));
    return;
  }
  canvas.save();
  canvas.clipPath(Path()..addOval(circle));
  canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      circle,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, opacity));
  canvas.restore();
}

/// Draws [size] logical pixels at [scale] (the game's screen's DPI over
/// 96), so the panel is as sharp as the screen.
Future<OverlayImage> _rasterize(
    Size size, double scale, void Function(Canvas canvas) paint,
    {List<TextPainter> dispose = const []}) async {
  final width = math.max(1, (size.width * scale).ceil());
  final height = math.max(1, (size.height * scale).ceil());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  paint(canvas);
  for (final painter in dispose) {
    painter.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return OverlayImage(width, height, bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
