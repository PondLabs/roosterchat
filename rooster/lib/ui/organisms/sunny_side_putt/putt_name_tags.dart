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

  /// Where the pointer under the pill sits, in pixels from the pill's
  /// middle: a tag stepped aside of its egg still points down at it.
  final double tail;

  /// How wide its egg draws, in pixels (0: unknown): a tag steps aside of
  /// it by at most one and a half of that, else it shrinks to its chip -
  /// farther, it read as naming someone else's egg.
  final double eggWidth;

  const PuttTag({
    required this.playerId,
    required this.name,
    required this.color,
    required this.at,
    this.dim = false,
    this.avatar,
    this.look = PuttLook.standard,
    this.compact = false,
    this.tail = 0,
    this.eggWidth = 0,
  });

  PuttTag _laidAt(Offset to,
          {required bool compact, required double tail, bool? dim}) =>
      PuttTag(
        playerId: playerId,
        name: name,
        color: color,
        at: to,
        dim: dim ?? this.dim,
        avatar: avatar,
        look: look,
        compact: compact,
        tail: tail,
        eggWidth: eggWidth,
      );
}

/// How tall the little egg on a tag stands, and how wide it is.
const double _tagEggSize = 13;
const double _tagEggWidth = _tagEggSize * 0.8;

/// The tags' places, refreshed once per rendered frame; the tag layer
/// listens.
class PuttTagBoard extends ChangeNotifier {
  List<PuttTag> _tags = const [];

  List<PuttTag> get tags => _tags;

  /// The tags for this frame, laid clear of each other, of [avoid] (the
  /// eggs, mine with its pin) and where they can of [soft] (the coach's
  /// hand and its aim). One that would stand under the [hud] (the top
  /// strip, the corner buttons) is not drawn: it would read as part of the
  /// HUD, and an egg that far up is under it too. Inside [screen] (the view
  /// less a margin) a tag running past an edge steps back in, its pointer
  /// still at its egg; one whose egg is off the screen is not drawn.
  void update(List<PuttTag> tags,
      {List<Rect> avoid = const [],
      List<Rect> soft = const [],
      List<Rect> hud = const [],
      Rect? screen}) {
    if (tags.isEmpty && _tags.isEmpty) return;
    final laid = declutterTags(tags, avoid: avoid, soft: soft);
    _tags = [
      for (final tag in laid)
        if (_kept(tag, screen) case final kept?)
          if (!hud.any((rect) => rect.overlaps(puttTagPill(kept, kept.at))))
            kept,
    ];
    notifyListeners();
  }

  /// [tag] inside [screen]: stepped in off an edge (its pointer leaning
  /// back to the egg it names), or none when that egg is off the screen.
  static PuttTag? _kept(PuttTag tag, Rect? screen) {
    if (screen == null) return tag;
    final egg = tag.at + Offset(tag.tail, 0);
    if (!screen.inflate(8).contains(egg)) return null;
    final pill = puttTagPill(tag, tag.at);
    var dx = 0.0;
    var dy = 0.0;
    if (pill.left < screen.left) dx = screen.left - pill.left;
    if (pill.right > screen.right) dx = screen.right - pill.right;
    if (pill.top < screen.top) dy = screen.top - pill.top;
    if (dx == 0 && dy == 0) return tag;
    final reach = math.max(0.0, pill.width / 2 - 9);
    return tag._laidAt(tag.at + Offset(dx, dy),
        compact: tag.compact, tail: (tag.tail - dx).clamp(-reach, reach));
  }
}

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

/// The tags laid clear of each other and of [avoid] (the eggs, mine with
/// its pin): eggs bunched on the tee would stack their pills on top of one
/// another. Each tag, from the lowest on screen up, tries its own spot,
/// then steps to either side, then rises a row past what is in the way -
/// but never far over another egg: a tag standing above someone else's
/// egg names that one. [soft] (the coach's hand and its aim, drawn
/// with a margin) is kept clear of while a spot by the egg allows it; a
/// tag with none then stands by its egg over that margin, its name shown
/// and faded back under the coach - failing that its picture alone, and
/// failing that it is not drawn this frame. A pill's size is read off its name, near enough for the layout.
List<PuttTag> declutterTags(List<PuttTag> tags,
    {List<Rect> avoid = const [], List<Rect> soft = const []}) {
  if (tags.isEmpty || (tags.length < 2 && avoid.isEmpty && soft.isEmpty)) {
    return tags;
  }
  final order = [...tags]..sort((a, b) => b.at.dy.compareTo(a.at.dy));
  final laidPills = <Rect>[];
  final laid = <String, PuttTag>{};
  final rows = tags.length + avoid.length + soft.length;
  for (final tag in order) {
    PuttTag? placed;
    for (final (compact, keepOff) in [
      (tag.compact, soft),
      (tag.compact, const <Rect>[]),
      (true, soft),
      (true, const <Rect>[]),
    ]) {
      placed = _layTag(tag, compact, laidPills, avoid, keepOff, rows);
      if (placed != null) break;
    }
    if (placed == null) continue;
    // Standing on the coach, it fades back: the gesture reads first.
    final pill = puttTagPill(placed, placed.at);
    if (!placed.dim && soft.any(pill.overlaps)) {
      placed = placed._laidAt(placed.at,
          compact: placed.compact, tail: placed.tail, dim: true);
    }
    laidPills.add(puttTagPill(placed, placed.at));
    laid[tag.playerId] = placed;
  }
  return [
    for (final tag in tags)
      if (laid[tag.playerId] case final placed?) placed,
  ];
}

/// How far a tag may rise over an egg or the coach in its way, in pixels:
/// over the top of a small, far egg, not over a whole one.
const double _tagRiseOverEgg = 40;

PuttTag? _layTag(PuttTag tag, bool compact, List<Rect> laidPills,
    List<Rect> eggs, List<Rect> soft, int rows) {
  final base = tag.at;
  final shape = tag._laidAt(base, compact: compact, tail: 0);
  final width = puttTagPill(shape, base).width;
  // The pointer reaches no further than the pill's rounded ends.
  final reach = math.max(0.0, width / 2 - 9);
  bool clear(Rect box) =>
      !laidPills.any(box.overlaps) &&
      !eggs.any(box.overlaps) &&
      !soft.any(box.overlaps);
  // How far aside of its egg it may stand.
  final aside =
      tag.eggWidth > 0 ? math.max(tag.eggWidth * 1.5, 18.0) : double.infinity;
  var y = base.dy;
  for (var row = 0; row <= rows; row++) {
    for (final dx in [
      0.0,
      -width * 0.6,
      width * 0.6,
      -width * 1.15,
      width * 1.15,
    ]) {
      if (dx.abs() > aside) continue;
      final at = Offset(base.dx + dx, y);
      if (clear(puttTagPill(shape, at))) {
        return tag._laidAt(at,
            compact: compact, tail: (-dx).clamp(-reach, reach));
      }
    }
    final box = puttTagPill(shape, Offset(base.dx, y));
    // Over another tag a tag may climb; over an egg or the coach only a
    // little way (a tag high over them stands by some other egg).
    final fixed = [
      ...eggs.where(box.overlaps),
      ...soft.where(box.overlaps),
    ];
    final hits = [...laidPills.where(box.overlaps), ...fixed];
    final next = hits.isEmpty
        ? y - 4
        : hits.map((other) => other.top).reduce(math.min) - 3;
    if (fixed.isNotEmpty && base.dy - next > _tagRiseOverEgg) return null;
    y = next;
  }
  return null;
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
        Transform.translate(
          offset: Offset(tag.tail, 0),
          child: CustomPaint(
            size: const Size(10, 5),
            painter: _PointerPainter(tag.color),
          ),
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
