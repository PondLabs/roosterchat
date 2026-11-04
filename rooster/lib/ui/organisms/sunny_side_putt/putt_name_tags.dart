// Name tags over the other players' eggs: who is who on a busy green. The
// game projects each egg's spot to the surface after every rendered frame
// ([PuttTagBoard.update]); the tags are plain Flutter pills riding those
// pixels - the player's colour dot and name, a little pointer down to the
// shell. The viewer's own egg has none: the bobbing arrow marks it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'putt_art.dart';

/// One tag: who, in which colour, at which surface pixel (the spot just
/// over the egg the pill points down to).
class PuttTag {
  final String playerId;
  final String name;
  final Color color;
  final Offset at;

  const PuttTag({
    required this.playerId,
    required this.name,
    required this.color,
    required this.at,
  });
}

/// The tags' places, refreshed once per rendered frame; the tag layer
/// listens.
class PuttTagBoard extends ChangeNotifier {
  List<PuttTag> _tags = const [];

  List<PuttTag> get tags => _tags;

  void update(List<PuttTag> tags) {
    if (tags.isEmpty && _tags.isEmpty) return;
    _tags = declutterTags(tags);
    notifyListeners();
  }
}

/// The tags lifted clear of each other: eggs bunched on the tee would
/// stack their pills on top of one another, so each tag (from the lowest
/// on screen up) rises above any it would overlap. A pill's size is read
/// off its name, near enough for the layout.
List<PuttTag> declutterTags(List<PuttTag> tags) {
  if (tags.length < 2) return tags;
  Rect pill(PuttTag tag, Offset at) {
    final width = 30.0 + tag.name.length * 7.2;
    return Rect.fromLTWH(at.dx - width / 2, at.dy - 26, width, 26);
  }

  final order = [...tags]..sort((a, b) => b.at.dy.compareTo(a.at.dy));
  final placed = <Rect>[];
  final moved = <String, Offset>{};
  for (final tag in order) {
    var at = tag.at;
    for (var pass = 0; pass < tags.length; pass++) {
      final box = pill(tag, at);
      final hit = placed.where((other) => other.overlaps(box)).toList();
      if (hit.isEmpty) break;
      final top = hit.map((other) => other.top).reduce(math.min);
      at = Offset(at.dx, top - 2);
    }
    placed.add(pill(tag, at));
    moved[tag.playerId] = at;
  }
  return [
    for (final tag in tags)
      PuttTag(
        playerId: tag.playerId,
        name: tag.name,
        color: tag.color,
        at: moved[tag.playerId] ?? tag.at,
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
                child: _TagPill(tag: tag),
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
          padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
          decoration: BoxDecoration(
            color: PuttPalette.ink.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tag.color, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: tag.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
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
