// The power-ups' icons: each of the twelve effects draws one of its own,
// at the carton's 28 px and the picker's 20 px, and inside its square; an
// id the set does not know falls back to the "?" carton.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/effects/effect_registry.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_powerup_icons.dart';

/// [effectId]'s icon at [size], with [margin] of empty space round it,
/// drawn at [ratio]: its pixels, RGBA.
Future<Uint8List> render(
  WidgetTester tester,
  String effectId,
  double size, {
  double margin = 0,
  double ratio = 1,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        key: key,
        child: Padding(
          padding: EdgeInsets.all(margin),
          child: PuttPowerUpIcon(effectId: effectId, size: size),
        ),
      ),
    ),
  ));
  expect(tester.takeException(), isNull);
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
  });
  return bytes!.buffer.asUint8List();
}

/// The share of [pixels] that something was painted on.
double coverage(Uint8List pixels) {
  var painted = 0;
  for (var i = 3; i < pixels.length; i += 4) {
    if (pixels[i] > 0) painted++;
  }
  return painted / (pixels.length ~/ 4);
}

void main() {
  final ids = builtinEffectIds.toList();

  testWidgets('every power-up draws an icon of its own, at 28 and 20 px',
      (tester) async {
    expect(ids, hasLength(12));
    for (final size in [28.0, 20.0]) {
      final fallback = await render(tester, 'no_such_power', size);
      final drawn = <String, Uint8List>{};
      for (final id in ids) {
        final pixels = await render(tester, id, size);
        expect(tester.getSize(find.byType(PuttPowerUpIcon)), Size.square(size));
        expect(
            find.descendant(
              of: find.byType(PuttPowerUpIcon),
              matching: find.byType(CustomPaint),
            ),
            findsOneWidget);
        expect(coverage(pixels), greaterThan(0.2),
            reason: '$id at $size px paints its shape');
        expect(pixels, isNot(equals(fallback)),
            reason: '$id at $size px is not the "?" carton');
        drawn[id] = pixels;
      }
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          expect(drawn[ids[i]], isNot(equals(drawn[ids[j]])),
              reason: '${ids[i]} and ${ids[j]} at $size px are told apart');
        }
      }
    }
  });

  testWidgets('an id the set does not know draws the "?" carton',
      (tester) async {
    for (final size in [28.0, 20.0]) {
      final carton = await render(tester, 'no_such_power', size);
      expect(coverage(carton), greaterThan(0.5),
          reason: 'the carton fills most of its square');
      expect(await render(tester, '', size), equals(carton));
      expect(await render(tester, 'next_seasons_power', size), equals(carton));
    }
  });

  testWidgets('every icon stays inside its square', (tester) async {
    const size = 28.0;
    const margin = 4.0;
    const ratio = 4.0;
    const side = (size + 2 * margin) * ratio;
    final square = Rect.fromLTWH(
        margin * ratio, margin * ratio, size * ratio, size * ratio);
    for (final id in [...ids, 'no_such_power']) {
      final pixels =
          await render(tester, id, size, margin: margin, ratio: ratio);
      var outside = 0;
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final alpha = pixels[(y * side.toInt() + x) * 4 + 3];
          if (alpha > 16 && !square.contains(Offset(x + 0.5, y + 0.5))) {
            outside++;
          }
        }
      }
      expect(outside, 0, reason: '$id paints over its neighbours');
    }
  });

  testWidgets('names itself to a screen reader only when given a label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        PuttPowerUpIcon(effectId: 'gust', size: 28, semanticLabel: 'Gust'),
        PuttPowerUpIcon(effectId: 'sprinkler', size: 28),
      ]),
    ));
    expect(find.bySemanticsLabel('Gust'), findsOneWidget);
    expect(
        tester.getSemantics(find.byType(PuttPowerUpIcon).last).label, isEmpty);
    semantics.dispose();
  });
}
