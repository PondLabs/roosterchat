import 'dart:async';

import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/utils/text_utils.dart';
import 'package:flutter/widgets.dart';

/// Fetches the preview of the link in a message that is still being written,
/// images included, so the message shows with its preview as soon as it is
/// sent. It is the request the timeline would make for the sent message,
/// made earlier; the timeline joins it or finds it cached.
/// See docs/link-previews.md.
class UrlPreviewPrefetcher {
  UrlPreviewPrefetcher({this.delay = const Duration(milliseconds: 300)});

  /// How long the text must rest first, so a link typed by hand isn't
  /// fetched at every keystroke. A pasted link waits only this long.
  final Duration delay;

  Timer? _timer;
  Uri? _last;

  void onTextChanged(BuildContext context, Room room, String text) {
    _timer?.cancel();
    _timer = Timer(delay, () => prefetch(context, room, text));
  }

  /// Starts fetching the preview the timeline will show for [text], if any.
  void prefetch(BuildContext context, Room room, String text) {
    if (!context.mounted || !room.shouldPreviewMedia) return;

    final component = room.client.getComponent<UrlPreviewComponent>();
    if (component == null) return;

    // The same link the timeline takes from the sent message.
    final link = TextUtils.findUrls(text)
        ?.where((link) => link.authority != "matrix.to")
        .firstOrNull;
    if (link == null || link == _last) return;
    if (!link.isScheme("https") && !link.isScheme("http")) return;
    if (!link.host.contains(".")) return;
    if (!component.shouldGetPreviewForLink(room, link)) return;

    _last = link;
    component.getPreviewForUrl(room, link).then((data) {
      if (data == null || !context.mounted) return;
      for (final image in UrlPreviewComponent.cardImages(data)) {
        precacheImage(image, context, onError: (_, __) {});
      }
    }, onError: (_) {});
  }

  void dispose() => _timer?.cancel();
}
