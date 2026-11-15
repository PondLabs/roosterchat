import 'dart:async';
import 'dart:ui' as ui;

import 'package:rooster/ui/atoms/lightbox.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_image_provider.dart';

/// A picture that downloads until the test says it has: [arrive] hands it
/// over. Every picture asked for is recorded in [asked].
class _SlowImage extends ImageProvider<_SlowImage> {
  _SlowImage(this.name);

  final String name;
  final _download = Completer<ImageInfo>();

  static final asked = <String>[];

  void arrive(ui.Image image) => _download.complete(ImageInfo(image: image));

  @override
  Future<_SlowImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_SlowImage>(this);

  @override
  ImageStreamCompleter loadImage(_SlowImage key, ImageDecoderCallback decode) {
    asked.add(name);
    return OneFrameImageStreamCompleter(_download.future);
  }

  @override
  String toString() => '_SlowImage($name)';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<ImageProvider>> photos(WidgetTester tester, int count) async {
    final result = <ImageProvider>[];
    for (var i = 0; i < count; i++) {
      final image = (await tester
          .runAsync(() => createTestImage(width: 100, height: 100)))!;
      result.add(FixedImageProvider(image));
    }
    return result;
  }

  testWidgets('gallery arrows step through the images and wrap around',
      (tester) async {
    final images = await photos(tester, 3);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Lightbox(image: images.first, gallery: images),
      ),
    ));
    await tester.pump();

    Image shown() => tester.widget<Image>(find.byType(Image));

    expect(shown().image, same(images[0]));

    await tester.tap(find.byKey(const ValueKey('lightbox-next')));
    await tester.pump();
    expect(shown().image, same(images[1]));

    await tester.tap(find.byKey(const ValueKey('lightbox-previous')));
    await tester.pump();
    expect(shown().image, same(images[0]));

    await tester.tap(find.byKey(const ValueKey('lightbox-previous')));
    await tester.pump();
    expect(shown().image, same(images[2]),
        reason: 'stepping back from the first image wraps to the last');
  });

  testWidgets('a single image has a close button but no arrows',
      (tester) async {
    final images = await photos(tester, 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Lightbox(image: images.first)),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('lightbox-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('lightbox-previous')), findsNothing);
    expect(find.byKey(const ValueKey('lightbox-next')), findsNothing);
  });

  testWidgets('the close button dismisses the modal', (tester) async {
    final images = await photos(tester, 2);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Lightbox.show(
              context,
              image: images.first,
              gallery: images,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Lightbox), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lightbox-close')));
    await tester.pumpAndSettle();
    expect(find.byType(Lightbox), findsNothing);
  });

  group('paging through many photos', () {
    setUp(() {
      _SlowImage.asked.clear();
      PaintingBinding.instance.imageCache.clear();
    });

    Future<void> pumpLightbox(WidgetTester tester, Lightbox lightbox) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: lightbox)));
      await tester.pump();
    }

    double frameRatio(WidgetTester tester) => tester
        .widget<AspectRatio>(find.ancestor(
            of: find.byKey(const ValueKey('lightbox-image')),
            matching: find.byType(AspectRatio)))
        .aspectRatio;

    BoxFit? imageFit(WidgetTester tester) =>
        tester.widget<Image>(find.byKey(const ValueKey('lightbox-image'))).fit;

    testWidgets('a counter says which photo is shown, of how many',
        (tester) async {
      final images = await photos(tester, 11);
      await pumpLightbox(tester, Lightbox(gallery: images, initialIndex: 3));

      expect(find.text('4 / 11'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lightbox-next')));
      await tester.pump();
      expect(find.text('5 / 11'), findsOneWidget);
    });

    testWidgets('a single image has no counter', (tester) async {
      final images = await photos(tester, 1);
      await pumpLightbox(tester, Lightbox(image: images.first));

      expect(find.byKey(const ValueKey('lightbox-position')), findsNothing);
    });

    testWidgets('the arrow keys step through the gallery', (tester) async {
      final images = await photos(tester, 3);
      await pumpLightbox(tester, Lightbox(gallery: images));
      Image shown() =>
          tester.widget<Image>(find.byKey(const ValueKey('lightbox-image')));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(shown().image, same(images[1]));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(shown().image, same(images[2]));
      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('a stepped-to photo takes its own shape before it loads',
        (tester) async {
      final gallery = [for (var i = 0; i < 3; i++) _SlowImage('full-$i')];
      await pumpLightbox(
          tester,
          Lightbox(
            gallery: gallery,
            galleryAspectRatios: const [1.5, 0.5, null],
          ));
      expect(frameRatio(tester), 1.5);

      await tester.tap(find.byKey(const ValueKey('lightbox-next')));
      await tester.pump();
      expect(frameRatio(tester), 0.5,
          reason: 'not the wide frame of the photo before');
      expect(imageFit(tester), BoxFit.cover);

      await tester.tap(find.byKey(const ValueKey('lightbox-next')));
      await tester.pump();
      expect(imageFit(tester), BoxFit.contain,
          reason: 'a photo of unknown shape is fitted whole, not cropped to '
              'the last one\'s shape');
    });

    testWidgets(
        'a photo that loads after the viewer moved on keeps its size '
        'to itself', (tester) async {
      final gallery = [for (var i = 0; i < 3; i++) _SlowImage('full-$i')];
      await pumpLightbox(
          tester,
          Lightbox(
            gallery: gallery,
            galleryAspectRatios: const [1.0, 1.0, 0.75],
          ));

      // Two steps before the first photo has arrived.
      await tester.tap(find.byKey(const ValueKey('lightbox-next')));
      await tester.tap(find.byKey(const ValueKey('lightbox-next')));
      await tester.pump();
      expect(frameRatio(tester), 0.75);

      final wide = (await tester
          .runAsync(() => createTestImage(width: 400, height: 100)))!;
      gallery[0].arrive(wide);
      gallery[1].arrive(wide.clone());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(frameRatio(tester), 0.75,
          reason: 'the late 4:1 answers belong to photos no longer shown');
    });

    testWidgets('the card\'s small copy shows while the large one loads',
        (tester) async {
      final small = await photos(tester, 2);
      final gallery = [_SlowImage('full-0'), _SlowImage('full-1')];
      await pumpLightbox(
          tester, Lightbox(gallery: gallery, galleryThumbnails: small));

      final thumbnail = find.byKey(const ValueKey('lightbox-thumbnail'));
      expect(tester.widget<Image>(thumbnail).image, same(small[0]));

      final picture = (await tester
          .runAsync(() => createTestImage(width: 100, height: 100)))!;
      gallery[0].arrive(picture);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(thumbnail, findsNothing);
    });

    testWidgets('the photos either side start downloading', (tester) async {
      final gallery = [for (var i = 0; i < 5; i++) _SlowImage('full-$i')];
      await pumpLightbox(tester, Lightbox(gallery: gallery, initialIndex: 2));
      await tester.pump();

      expect(_SlowImage.asked, containsAll(['full-1', 'full-2', 'full-3']));
      expect(_SlowImage.asked, isNot(contains('full-0')),
          reason: 'only the neighbours, not the whole gallery');
    });
  });
}
