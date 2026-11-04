// Name tags over the other players' eggs: who is who on a busy green. The
// game projects each egg's spot to the surface after every rendered frame
// ([PuttTagBoard.update]); the tags are plain Flutter pills riding those
// pixels - the player's colour dot and name, a little pointer down to the
// shell. The viewer's own egg has none: the bobbing arrow marks it.
library;

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
    _tags = tags;
    notifyListeners();
  }
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
