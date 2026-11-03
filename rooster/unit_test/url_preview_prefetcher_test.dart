import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/ui/organisms/chat/url_preview_prefetcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_image_provider.dart';

class _FakeComponent implements UrlPreviewComponent {
  final List<Uri> requested = [];
  bool previewsLinks = true;
  UrlPreviewData? result;

  @override
  bool shouldGetPreviewForLink(Room room, Uri link) => previewsLinks;

  @override
  Future<UrlPreviewData?> getPreviewForUrl(Room room, Uri url) async {
    requested.add(url);
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  _FakeClient(this.component);

  final UrlPreviewComponent component;

  @override
  T? getComponent<T extends Component>() =>
      component is T ? component as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  _FakeRoom(this.client);

  @override
  final Client client;

  @override
  bool shouldPreviewMedia = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeComponent component;
  late _FakeRoom room;
  late UrlPreviewPrefetcher prefetcher;

  setUp(() {
    component = _FakeComponent();
    room = _FakeRoom(_FakeClient(component));
    prefetcher = UrlPreviewPrefetcher();
  });

  tearDown(() => prefetcher.dispose());

  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(Builder(builder: (c) {
      context = c;
      return const SizedBox();
    }));
    return context;
  }

  testWidgets('fetches the link once the text has rested', (tester) async {
    final context = await pumpContext(tester);

    for (final text in [
      'look',
      'look https://youtu.be/dQw4w9WgXcQ',
      'look https://youtu.be/dQw4w9WgXcQ at this',
    ]) {
      prefetcher.onTextChanged(context, room, text);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(component.requested, isEmpty);

    await tester.pump(prefetcher.delay);
    expect(component.requested, [Uri.parse('https://youtu.be/dQw4w9WgXcQ')]);
  });

  testWidgets('fetches at once when the message is sent', (tester) async {
    final context = await pumpContext(tester);

    prefetcher.prefetch(context, room, 'https://example.com/a and more');

    expect(component.requested, [Uri.parse('https://example.com/a')]);
  });

  testWidgets('does not fetch a link it has already fetched', (tester) async {
    final context = await pumpContext(tester);

    prefetcher.prefetch(context, room, 'https://example.com/a');
    prefetcher.prefetch(context, room, 'https://example.com/a!');

    expect(component.requested, hasLength(1));
  });

  testWidgets('only fetches what the timeline would preview', (tester) async {
    final context = await pumpContext(tester);

    prefetcher.prefetch(context, room, 'https://matrix.to/#/@a:example.com');
    prefetcher.prefetch(context, room, 'https://localhost/page');
    prefetcher.prefetch(context, room, 'www.example.com/no-scheme');

    component.previewsLinks = false; // an encrypted room, previews off
    prefetcher.prefetch(context, room, 'https://example.com/private');

    component.previewsLinks = true;
    room.shouldPreviewMedia = false; // media previews off in this room
    prefetcher.prefetch(context, room, 'https://example.com/hidden');

    expect(component.requested, isEmpty);
  });

  testWidgets('loads the preview\'s image before the message is sent',
      (tester) async {
    final context = await pumpContext(tester);
    final image = FixedImageProvider(
        (await tester.runAsync(() => createTestImage(width: 64, height: 64)))!);
    component.result = UrlPreviewData(
      Uri.parse('https://example.com/a'),
      title: 'A page',
      image: image,
    );

    prefetcher.prefetch(context, room, 'https://example.com/a');
    await tester.pump();

    expect(PaintingBinding.instance.imageCache.containsKey(image), isTrue);
  });
}
