import 'dart:math';

import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/components/video_embed/composite_video_provider.dart';
import 'package:rooster/client/components/video_embed/video_embed_info.dart';
import 'package:rooster/client/components/video_embed/video_playback_source.dart';
import 'package:rooster/ui/atoms/lightbox.dart';
import 'package:rooster/ui/atoms/message_attachment.dart';
import 'package:rooster/ui/atoms/shimmer_loading.dart';
import 'package:rooster/ui/molecules/video_player/video_playback_dialog.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:rooster/client/components/video_embed/x_post.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart' as intl;
import 'package:tiamat/atoms/avatar.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

typedef VideoPreviewOpener = Future<void> Function(
  BuildContext context,
  VideoEmbedInfo video,
  bool autoplay,
);

class UrlPreviewWidget extends StatefulWidget {
  const UrlPreviewWidget(
    this.data, {
    super.key,
    this.onOpenLink,
    this.onOpenVideo,
    this.provider,
    this.supportsOfficialEmbeds,
  });

  final UrlPreviewData? data;
  final void Function()? onOpenLink;
  final VideoPreviewOpener? onOpenVideo;
  final CompositeVideoProvider? provider;

  /// Overrides [VideoPlaybackDialog.supportsOfficialEmbeds], for tests.
  final bool? supportsOfficialEmbeds;

  @override
  State<UrlPreviewWidget> createState() => _UrlPreviewWidgetState();
}

class _UrlPreviewWidgetState extends State<UrlPreviewWidget> {
  double titleWidth = 0;
  double bodyWidth1 = 0;
  double bodyWidth2 = 0;

  bool isLoadingPlayback = false;

  @override
  void initState() {
    final rng = Random();
    titleWidth = (rng.nextDouble() * 50) + 50;
    bodyWidth1 = (rng.nextDouble() * 200) + 100;
    bodyWidth2 = (rng.nextDouble() * 200) + 100;

    super.initState();
  }

  @override
  void didChangeDependencies() {
    setState(() {});
    super.didChangeDependencies();
  }

  CompositeVideoProvider get provider =>
      widget.provider ?? CompositeVideoProvider.instance;

  bool get supportsOfficialEmbeds =>
      widget.supportsOfficialEmbeds ??
      VideoPlaybackDialog.supportsOfficialEmbeds;

  // Not provider.canHandle: providers claim links that may not hold a video
  // (X posts with only text or photos), so trust what the preview resolved.
  bool get isVideo =>
      widget.data?.type == UrlDestinationType.video ||
      widget.data?.videoEmbedInfo != null;

  bool get isShortForm => widget.data?.videoEmbedInfo?.isShortForm ?? false;

  // Photo posts get media-card scale (like videos), not the compact page card.
  bool get isPhotoPost =>
      widget.data?.images.isNotEmpty == true ||
      widget.data?.type == UrlDestinationType.image;

  bool get isGallery => (widget.data?.images.length ?? 0) > 1;

  // A link straight to an image has nothing to say besides the image, so it
  // shows the image alone, like an image attachment, with no card around it.
  bool get isBareImage =>
      !hasBody &&
      !isVideo &&
      !isGallery &&
      widget.data?.image != null &&
      widget.data?.video == null;

  // Discord-style link embeds put a page's og:image on the right as a small
  // thumbnail, and reserve full media below the text for videos and photos.
  bool get isPageThumbnail =>
      hasBody &&
      !isVideo &&
      !isPhotoPost &&
      widget.data?.image != null &&
      widget.data?.video == null;

  Future<void> _openVideo({required bool autoplay}) async {
    setState(() {
      isLoadingPlayback = true;
    });

    try {
      final uri = widget.data?.uri;
      if (uri != null) {
        final resolved = await _resolvePlayback(uri);
        // Nothing here can play it: either no provider knows the link (an
        // og:video that is an HTML player page), or there is no web view to
        // host the provider's player (issue #19). Hand it to the browser.
        if (resolved == null ||
            (resolved.playbackSource is OfficialVideoEmbedSource &&
                !supportsOfficialEmbeds)) {
          if (mounted) {
            setState(() => isLoadingPlayback = false);
            _openLink();
          }
          return;
        }
        if (mounted) {
          setState(() => isLoadingPlayback = false);
          final opener = widget.onOpenVideo ??
              (context, video, auto) => VideoPlaybackDialog.show(
                    context,
                    video: video,
                    autoplay: auto,
                  );
          await opener(context, resolved, autoplay);
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => isLoadingPlayback = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Video unavailable. Please try again.'),
        ),
      );
    }
  }

  Future<VideoEmbedInfo?> _resolvePlayback(Uri uri) async {
    final current = widget.data?.videoEmbedInfo;
    if (current?.playbackSource != null) return current;

    final streamUrl = widget.data?.video?.streamUrl;
    if (streamUrl != null) {
      return (current ??
              VideoEmbedInfo(
                originalUrl: uri,
                title: widget.data?.title ?? 'Video',
                platformName: widget.data?.siteName ?? 'Video',
                aspectRatio: widget.data?.video?.aspectRatio,
              ))
          .copyWith(playbackSource: NativeVideoSource(streamUrl));
    }

    if (!provider.canHandle(uri)) return null;
    return await provider.resolve(uri, fetchPlayback: true);
  }

  void _openLink() {
    if (widget.onOpenLink != null) {
      widget.onOpenLink?.call();
    } else if (widget.data?.uri != null) {
      LinkUtils.open(widget.data!.uri, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final xPost = widget.data?.xPost;
    if (xPost != null) return _buildXCard(xPost);
    if (isBareImage) return _buildBareImage();

    final double maxWidth;
    final double maxHeight;
    if (isVideo) {
      maxWidth = isShortForm ? 280 : 480;
      maxHeight = isShortForm ? 480 : 420;
    } else if (isPhotoPost) {
      maxWidth = 480;
      // Room for the text body plus a media cap of 480; the photo shrinks
      // within what is left, so the card never overflows.
      maxHeight = 620;
    } else {
      maxWidth = 480;
      maxHeight = isPageThumbnail ? double.infinity : 420;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Tile.surfaceContainer(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('url-preview-card'),
            onTap: widget.data == null || (isVideo && isLoadingPlayback)
                ? null
                : isVideo
                    ? () => _openVideo(autoplay: false)
                    : _openLink,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: maxWidth,
                        maxHeight: maxHeight,
                      ),
                      child: widget.data == null
                          ? buildLoadingDisplay()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                if (isPageThumbnail)
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: body(context)),
                                      const SizedBox(width: 10),
                                      _buildPageThumbnail(),
                                    ],
                                  )
                                else ...[
                                  Align(
                                    alignment: Alignment.topLeft,
                                    child: body(context),
                                  ),
                                  if (hasBody)
                                    const SizedBox(
                                      width: 10,
                                      height: 10,
                                    ),
                                  if (isVideo)
                                    Flexible(child: _buildVideoThumbnail())
                                  else if (isGallery)
                                    Flexible(child: _buildPhotoGrid())
                                  else if (widget.data!.image != null &&
                                      widget.data?.video == null)
                                    Flexible(
                                      child: isPhotoPost
                                          ? ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  maxHeight: 480),
                                              child: image(),
                                            )
                                          : image(),
                                    )
                                  else if (widget.data!.video != null)
                                    MessageAttachment(
                                      previewMedia: true,
                                      widget.data!.video!,
                                      constrainSize: false,
                                    ),
                                ],
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail() {
    final aspect = widget.data?.videoEmbedInfo?.aspectRatio ??
        (isShortForm ? (9.0 / 16.0) : (16.0 / 9.0));
    final platformName =
        widget.data?.videoEmbedInfo?.platformName ?? widget.data?.siteName;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Material(
        color: Colors.black26,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.data?.image != null)
              AspectRatio(
                aspectRatio: aspect,
                child: Image(
                  image: widget.data!.image!,
                  filterQuality: FilterQuality.medium,
                  fit: BoxFit.cover,
                ),
              )
            else
              AspectRatio(
                aspectRatio: aspect,
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ),
            if (isLoadingPlayback)
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              )
            else
              InkWell(
                key: const ValueKey('url-preview-play'),
                onTap: () => _openVideo(autoplay: true),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            if (platformName != null)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  key: const ValueKey('url-preview-badge'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isShortForm)
                        const Padding(
                          padding: EdgeInsets.only(right: 3.0),
                          child: Icon(
                            Icons.bolt,
                            size: 13,
                            color: Colors.redAccent,
                          ),
                        ),
                      Text(
                        platformName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (widget.data?.videoEmbedInfo?.duration != null)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(widget.data!.videoEmbedInfo!.duration!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (duration.inHours > 0) {
      final hours = duration.inHours;
      final remMinutes = minutes % 60;
      return '$hours:${remMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget buildLoadingDisplay() {
    final color = Theme.of(context).colorScheme.surfaceContainerLowest;
    return Shimmer(
      child: ShimmerLoading(
        isLoading: true,
        child: SizedBox(
          height: 300,
          child: Row(
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: titleWidth,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: bodyWidth1,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      height: 10,
                      width: bodyWidth2,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 180,
                          maxWidth: 300,
                        ),
                        child: Container(color: color),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget image() {
    final photos = widget.data!.images;
    final picture = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: widget.data?.type != UrlDestinationType.video
            ? () {
                Lightbox.show(context, image: widget.data!.image);
              }
            : null,
        child: Image(
          image: widget.data!.image!,
          filterQuality: FilterQuality.medium,
          fit: BoxFit.cover,
        ),
      ),
    );

    // Post media knows its dimensions up front, so reserve the space instead
    // of letting the card jump when the photo loads.
    final aspectRatio = photos.isEmpty ? null : photos.first.aspectRatio;
    if (aspectRatio == null || aspectRatio <= 0) return picture;
    return AspectRatio(aspectRatio: aspectRatio, child: picture);
  }

  /// Media-card scale, like photo posts. Small images keep their own size.
  Widget _buildBareImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('url-preview-image'),
          onTap: () => Lightbox.show(context, image: widget.data!.image),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
            child: Image(
              image: widget.data!.image!,
              filterQuality: FilterQuality.medium,
              fit: BoxFit.contain,
              // The link led somewhere that isn't an image after all (a 403
              // page, a dead link): show nothing rather than a broken image.
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  /// A page's og:image, right-aligned and small, the way Discord frames
  /// link embeds with a thumbnail instead of a hero image.
  Widget _buildPageThumbnail() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => Lightbox.show(context, image: widget.data!.image),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120, maxHeight: 120),
          child: Image(
            image: widget.data!.image!,
            filterQuality: FilterQuality.medium,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  static const double _photoGridGap = 4;

  /// X's layout: 2 photos side by side, 3 as one large photo next to two
  /// stacked ones, 4 as a 2x2. Cells are cropped squares; each opens in the
  /// lightbox on tap, like multi-image room messages. The lightbox pages
  /// through every photo, including those an Instagram carousel has past
  /// the fourth.
  Widget _buildPhotoGrid() {
    final photos = widget.data!.images.take(4).toList();
    final gallery = [for (final photo in widget.data!.images) photo.image];

    return LayoutBuilder(builder: (context, constraints) {
      const gap = _photoGridGap;

      if (photos.length == 3) {
        final large =
            min((constraints.maxWidth - gap) * 2 / 3, constraints.maxHeight);
        final small = (large - gap) / 2;
        if (small <= 0) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _photoCell(photos[0], gallery, 0, large),
            const SizedBox(width: gap),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _photoCell(photos[1], gallery, 1, small),
                const SizedBox(height: gap),
                _photoCell(photos[2], gallery, 2, small),
              ],
            ),
          ],
        );
      }

      final rows = photos.length <= 2 ? 1 : 2;
      final cell = min(
          (constraints.maxWidth - gap) / 2,
          rows == 1
              ? constraints.maxHeight
              : (constraints.maxHeight - gap) / 2);
      if (cell <= 0) return const SizedBox.shrink();

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var row = 0; row < (photos.length + 1) ~/ 2; row++) ...[
            if (row > 0) const SizedBox(height: gap),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _photoCell(photos[row * 2], gallery, row * 2, cell),
                if (row * 2 + 1 < photos.length) ...[
                  const SizedBox(width: gap),
                  _photoCell(photos[row * 2 + 1], gallery, row * 2 + 1, cell),
                ],
              ],
            ),
          ],
        ],
      );
    });
  }

  Widget _photoCell(UrlPreviewImage photo, List<ImageProvider> gallery,
      int index, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: () => Lightbox.show(
          context,
          image: photo.image,
          gallery: gallery,
          initialIndex: index,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Image(
            image: photo.image,
            filterQuality: FilterQuality.medium,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  bool get hasBody =>
      widget.data?.siteName != null ||
      widget.data?.title != null ||
      widget.data?.description != null;

  // Discord-style preview hierarchy: 14 site line, 16 bold title, 14 body,
  // 12 footer link. Applies to every preview (X, YouTube, Instagram, pages).
  Widget body(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final secondary = theme.colorScheme.secondary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.data!.siteName != null)
          Text(
            widget.data!.siteName!,
            style: textTheme.labelLarge!.copyWith(
              fontWeight: FontWeight.w400,
              color: secondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.fade,
          ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.data!.title != null)
              Text(
                widget.data!.title!,
                style: textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (widget.data!.title != null && widget.data!.description != null)
              const SizedBox(height: 2),
            if (widget.data!.description != null)
              Text(
                widget.data!.description!,
                style: textTheme.bodyMedium!.copyWith(color: secondary),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            // Explicit External Link affordance
            InkWell(
              key: const ValueKey('url-preview-external-link'),
              onTap: _openLink,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.data!.uri.toString(),
                        style: textTheme.bodySmall!.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // The X logo (simple-icons), so the card needs no asset.
  static const _xLogoSvg =
      '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path '
      'd="M18.901 1.153h3.68l-8.04 9.19L24 22.846h-7.406l-5.8-7.584-6.638 '
      '7.584H.474l8.6-9.83L0 1.154h7.594l5.243 6.932ZM17.61 20.644h2.039L6.486 '
      '3.24H4.298Z"/></svg>';

  /// iframely's X card: author, text, media, quoted post, date and counts.
  /// The whole card opens the post. See docs/x-posts.md.
  Widget _buildXCard(XPost post) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.secondary;
    final images = widget.data!.images;
    final Widget? media = images.length > 1
        ? _buildPhotoGrid()
        : images.length == 1
            ? image()
            : isVideo
                ? _buildVideoThumbnail()
                : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Tile.surfaceContainer(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('url-preview-card'),
            onTap: _openLink,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _xAuthor(post, radius: 20)),
                        const SizedBox(width: 8),
                        SvgPicture.string(
                          _xLogoSvg,
                          key: const ValueKey('x-logo'),
                          width: 18,
                          height: 18,
                          colorFilter: ColorFilter.mode(
                              theme.colorScheme.onSurface, BlendMode.srcIn),
                        ),
                      ],
                    ),
                    if (post.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(children: _xText(post.text)),
                        style: theme.textTheme.bodyMedium,
                        maxLines: 12,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (media != null) ...[
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: media,
                      ),
                    ],
                    if (post.quote != null) ...[
                      const SizedBox(height: 8),
                      _xQuote(post.quote!),
                    ],
                    const SizedBox(height: 8),
                    DefaultTextStyle.merge(
                      style:
                          theme.textTheme.bodySmall!.copyWith(color: secondary),
                      child: IconTheme.merge(
                        data: IconThemeData(size: 15, color: secondary),
                        child: Row(
                          children: [
                            _xCount(Icons.chat_bubble_outline, post.replies),
                            _xCount(Icons.repeat, post.retweets),
                            _xCount(Icons.favorite_border, post.likes),
                            const Spacer(),
                            if (post.createdAt != null)
                              Flexible(
                                flex: 3,
                                child: Text(
                                  intl.DateFormat.yMMMd()
                                      .add_jm()
                                      .format(post.createdAt!.toLocal()),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Avatar, display name, verified mark and @handle.
  Widget _xAuthor(XPost post, {required double radius}) {
    final theme = Theme.of(context);
    final avatar = post.avatarUrl;
    return Row(
      children: [
        Avatar(
          radius: radius,
          image: avatar == null ? null : NetworkImage(avatar.toString()),
          placeholderText: post.authorName,
          placeholderColor: theme.colorScheme.surfaceContainerHighest,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      post.authorName,
                      style: theme.textTheme.titleSmall!
                          .copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (post.isVerified)
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Icon(
                        Icons.verified,
                        key: const ValueKey('x-verified'),
                        size: 16,
                        // X's colours: gold for businesses, grey for
                        // governments, blue otherwise.
                        color: switch (post.verification) {
                          'business' => const Color(0xFFE2B719),
                          'government' => const Color(0xFF829AAB),
                          _ => const Color(0xFF1D9BF0),
                        },
                      ),
                    ),
                ],
              ),
              Text(
                '@${post.handle}',
                style: theme.textTheme.bodySmall!
                    .copyWith(color: theme.colorScheme.secondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static final _xEntity = RegExp(r'https?://\S+|@\w{1,15}|#\w+');

  /// The post's text with links, @mentions and #hashtags tappable.
  // ponytail: recognizers are not disposed, like LinkSpan's.
  List<InlineSpan> _xText(String text) {
    final theme = Theme.of(context);
    final linkColor =
        theme.extension<ExtraColors>()?.linkColor ?? theme.colorScheme.primary;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _xEntity.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(last, match.start)));
      final entity = match[0]!;
      final target = switch (entity[0]) {
        '@' => Uri.https('x.com', '/${entity.substring(1)}'),
        '#' => Uri.https('x.com', '/hashtag/${entity.substring(1)}'),
        _ => Uri.tryParse(entity),
      };
      spans.add(TextSpan(
        text: entity,
        style: TextStyle(color: linkColor),
        recognizer: target == null
            ? null
            : (TapGestureRecognizer()
              ..onTap = () => LinkUtils.open(target, context: context)),
      ));
      last = match.end;
    }
    spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }

  /// The quoted post, nested and smaller; tapping it opens the quote.
  Widget _xQuote(XPost quote) {
    final theme = Theme.of(context);
    final thumbnail = quote.media.firstOrNull?.thumbnailUrl;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('x-quote'),
        onTap: () => LinkUtils.open(quote.url, context: context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _xAuthor(quote, radius: 11),
              if (quote.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  quote.text,
                  style: theme.textTheme.bodySmall,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (thumbnail != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: Image.network(
                      thumbnail.toString(),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _xCount(IconData icon, int count) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(width: 4),
            Text(intl.NumberFormat.compact().format(count)),
          ],
        ),
      );
}
