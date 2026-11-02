// The people in a voice channel as one tile: one face fills it, two sit
// corner to corner, three make a triangle, four a grid, and a fuller
// channel's fourth cell counts the rest. See docs/whos-around.md.
import 'package:rooster/client/member.dart';
import 'package:flutter/material.dart';

class FaceCluster extends StatelessWidget {
  const FaceCluster({
    required this.members,
    required this.total,
    required this.size,
    this.radius,
    this.tileColor,
    super.key,
  });

  /// Up to four of the people, in the order they are shown.
  final List<Member> members;

  /// How many there are in all, counted in the fourth cell past four.
  final int total;

  final double size;

  /// The tile's corner radius; a space icon's by default.
  final double? radius;

  /// Behind the faces, and the outline that lifts one face off another.
  final Color? tileColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tile = tileColor ?? colors.surfaceContainerHigh;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size / 3.4),
      child: ColoredBox(
        color: tile,
        child: SizedBox.square(
          dimension: size,
          child: _layout(context, tile),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, Color tile) {
    final colors = Theme.of(context).colorScheme;
    final shown = members.take(4).toList();
    switch (shown.length) {
      case 0:
        return const SizedBox.shrink();
      case 1:
        return Face(shown[0], size: size, radius: 0);
      case 2:
        final face = size * 0.64;
        return Stack(children: [
          Positioned(
              left: 0,
              top: 0,
              child: Face(shown[0], size: face, radius: face / 3)),
          Positioned(
              right: 0,
              bottom: 0,
              child:
                  Face(shown[1], size: face, radius: face / 3, border: tile)),
        ]);
      case 3:
        final face = size * 0.48;
        return Stack(children: [
          Positioned(
              left: (size - face) / 2,
              top: 0,
              child: Face(shown[0], size: face, radius: face / 3)),
          Positioned(
              left: 0,
              bottom: 0,
              child: Face(shown[1], size: face, radius: face / 3)),
          Positioned(
              right: 0,
              bottom: 0,
              child: Face(shown[2], size: face, radius: face / 3)),
        ]);
      default:
        const gap = 2.0;
        final face = (size - gap * 3) / 2;
        final radius = face / 3;
        Widget cell(int index) {
          if (index == 3 && total > 4) {
            return SizedBox(
              width: face,
              height: face,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Center(
                  child: Text(
                    "+${total - 3}",
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: face * 0.42,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: colors.onSurfaceVariant),
                  ),
                ),
              ),
            );
          }
          return Face(shown[index], size: face, radius: radius);
        }

        return Stack(children: [
          Positioned(left: gap, top: gap, child: cell(0)),
          Positioned(left: gap * 2 + face, top: gap, child: cell(1)),
          Positioned(left: gap, top: gap * 2 + face, child: cell(2)),
          Positioned(left: gap * 2 + face, top: gap * 2 + face, child: cell(3)),
        ]);
    }
  }
}

/// Someone's avatar, or their initial on their colour.
class Face extends StatelessWidget {
  const Face(this.member,
      {required this.size, required this.radius, this.border, super.key});

  final Member member;
  final double size;
  final double radius;

  /// Outlines the face in this colour, to lift it off a face behind it.
  final Color? border;

  @override
  Widget build(BuildContext context) {
    // A member not loaded yet is its user id: its first letter, not the @.
    final name = member.displayName.replaceFirst("@", "");
    final initial = name.isEmpty ? "" : name.characters.first.toUpperCase();
    final placeholder = ColoredBox(
      color: member.defaultColor,
      child: Center(
        child: Text(
          initial,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontSize: size / 2, height: 1),
        ),
      ),
    );
    final image = member.avatar;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!, width: 2),
      ),
      child: image == null
          ? placeholder
          : Image(
              image: image,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}
