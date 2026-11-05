// Name tags over the other players' eggs: who is who on a busy green. The
// game projects each egg's spot to the surface after every rendered frame
// ([PuttTagBoard.update]); the tags are plain Flutter pills riding those
// pixels - the player's picture, their little egg (their colour, their
// pattern, their chick's hat) and their name, a little pointer down to
// the shell. The viewer's own egg has none: the bobbing arrow marks it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rooster/client/components/sunny_side_putt/core/look.dart';

import 'putt_art.dart';
import 'putt_look.dart';

/// One tag: who, in which colour, at which surface pixel (the spot just
/// over the egg the pill points down to).
class PuttTag {
  final String playerId;
  final String name;
  final Color color;
  final Offset at;

  /// Faded back (while I aim, the green ahead matters more).
  final bool dim;

  /// The player's picture, when they have one.
  final ImageProvider? avatar;

  /// Their pattern and their chick's hat, on the little egg by the name.
  final PuttLook look;

  /// Just the picture (or the little egg), no name: the camera is far and
  /// the names would cover the eggs.
  final bool compact;

  const PuttTag({
    required this.playerId,
    required this.name,
    required this.color,
    required this.at,
    this.dim = false,
    this.avatar,
    this.look = PuttLook.standard,
    this.compact = false,
  });
}

/// How tall the little egg on a tag stands, and how wide it is.
const double _tagEggSize = 13;
const double _tagEggWidth = _tagEggSize * 0.8;

/// The tags' places, refreshed once per rendered frame; the tag layer
/// listens.
class PuttTagBoard extends ChangeNotifier {
  List<PuttTag> _tags = const [];

  List<PuttTag> get tags => _tags;

  /// The tags for this frame, laid clear of each other and of [avoid]
  /// (the eggs, mine with its pin). One that would stand under the [hud]
  /// (the top strip, the corner buttons) is not drawn: it would read as part
  /// of the HUD, and an egg that far up is under it too.
  void update(List<PuttTag> tags,
      {List<Rect> avoid = const [], List<Rect> hud = const []}) {
    if (tags.isEmpty && _tags.isEmpty) return;
    final laid = declutterTags(tags, avoid: avoid);
    _tags = [
      for (final tag in laid)
        if (!hud.any((rect) => rect.overlaps(puttTagPill(tag, tag.at)))) tag,
    ];
    notifyListeners();
  }
}

/// The tags lifted clear of each other: eggs bunched on the tee would
/// stack their pills on top of one another, so each tag (from the lowest
/// on screen up) rises above any it would overlap. A pill's size is read
/// off its name, near enough for the layout.
/// A tag's pill as drawn, anchored at [at] (the tip of its tail): its
/// padding and border, the picture and the little egg (only one of them
/// when compact), the gap and the name at about 7.4 px a letter, and the
/// tail under it.
Rect puttTagPill(PuttTag tag, Offset at) {
  final picture = tag.avatar != null;
  final mark = tag.compact
      ? (picture ? 18.0 : _tagEggWidth)
      : (picture ? 18.0 + 3 + _tagEggWidth : _tagEggWidth);
  final width = tag.compact
      ? mark + 9
      : (19 + mark + 5 + tag.name.length * 7.4).clamp(0.0, 150.0);
  const height = 32.0;
  return Rect.fromLTWH(at.dx - width / 2, at.dy - height, width, height);
}

List<PuttTag> declutterTags(List<PuttTag> tags, {List<Rect> avoid = const []}) {
  if (tags.isEmpty || (tags.length < 2 && avoid.isEmpty)) return tags;
  final order = [...tags]..sort((a, b) => b.at.dy.compareTo(a.at.dy));
  final placed = <Rect>[...avoid];
  final moved = <String, Offset>{};
  for (final tag in order) {
    final base = tag.at;
    final width = puttTagPill(tag, base).width;
    Offset? chosen;
    var y = base.dy;
    // Where it stands, then a little to either side, then up a row past
    // whatever is in the way, and the same again.
    for (var row = 0;
        row <= tags.length + avoid.length && chosen == null;
        row++) {
      for (final dx in [0.0, -width * 0.6, width * 0.6]) {
        final at = Offset(base.dx + dx, y);
        final box = puttTagPill(tag, at);
        if (!placed.any((other) => other.overlaps(box))) {
          chosen = at;
          break;
        }
      }
      if (chosen != null) break;
      final box = puttTagPill(tag, Offset(base.dx, y));
      final hits = placed.where((other) => other.overlaps(box));
      y = hits.isEmpty
          ? y - 4
          : hits.map((other) => other.top).reduce(math.min) - 3;
    }
    chosen ??= Offset(base.dx, y);
    placed.add(puttTagPill(tag, chosen));
    moved[tag.playerId] = chosen;
  }
  return [
    for (final tag in tags)
      PuttTag(
        playerId: tag.playerId,
        name: tag.name,
        color: tag.color,
        at: moved[tag.playerId] ?? tag.at,
        dim: tag.dim,
        avatar: tag.avatar,
        look: tag.look,
        compact: tag.compact,
      ),
  ];
}

/// The tag layer: a pill per tag, laid at its pixel.
class PuttNameTags extends StatelessWidget {
  final PuttTagBoard board;

  const PuttNameTags({super.key, required this.board});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: board,
      builder: (context, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (final tag in board.tags)
            Positioned(
              left: tag.at.dx,
              top: tag.at.dy,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -1),
                // Dimmed while I aim, still readable.
                child: Opacity(
                  opacity: tag.dim ? 0.6 : 1,
                  child: _TagPill(tag: tag),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  final PuttTag tag;

  const _TagPill({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 150),
          padding: tag.compact
              ? const EdgeInsets.all(3)
              : const EdgeInsets.fromLTRB(7, 3, 9, 3),
          decoration: BoxDecoration(
            color: PuttPalette.ink.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tag.color, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tag.avatar != null)
                // The player's picture in a ring of their colour.
                Container(
                  width: 18,
                  height: 18,
                  padding: const EdgeInsets.all(1.5),
                  decoration:
                      BoxDecoration(color: tag.color, shape: BoxShape.circle),
                  child: ClipOval(
                    child: Image(
                      image: tag.avatar!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, __) =>
                          ColoredBox(color: tag.color),
                    ),
                  ),
                ),
              // Their little egg: the colour, the pattern, the hat.
              if (tag.avatar == null || !tag.compact) ...[
                if (tag.avatar != null) const SizedBox(width: 3),
                PuttEggGlyph(
                  key: Key('putt-tag-egg-${tag.playerId}'),
                  tint: tag.color,
                  look: tag.look,
                  size: _tagEggSize,
                ),
              ],
              if (!tag.compact) const SizedBox(width: 5),
              if (!tag.compact)
                Flexible(
                  child: Text(
                    tag.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PuttPalette.cream,
                      fontFamily: 'NunitoSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ),
            ],
          ),
        ),
        CustomPaint(
          size: const Size(10, 5),
          painter: _PointerPainter(tag.color),
        ),
      ],
    );
  }
}

/// The little triangle under the pill, pointing down at the egg.
class _PointerPainter extends CustomPainter {
  final Color color;

  const _PointerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) => oldDelegate.color != color;
}
