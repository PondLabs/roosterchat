import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/components/video_embed/x_post.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// The text of an X post in its card: all of it when it takes [wholeLines]
/// lines or fewer, else its first [foldedLines] over a "Show more" button
/// that shows the rest in place, and "Show less" to fold it back. The text
/// is never cut without that button. See docs/x-posts.md.
class XPostText extends StatefulWidget {
  const XPostText(
    this.text, {
    super.key,
    required this.name,
    required this.wholeLines,
    required this.foldedLines,
    this.style,
    this.onOpenLink,
  });

  /// The linked post's text. Of 470 recent posts laid out in the card's
  /// text style in November 2026, none of the 386 ordinary ones (280
  /// characters at most) passed 15 lines at the card's width or at a
  /// phone's, nor 18 on a phone with text at 1.3x, so those always show
  /// whole; only X's long posts (up to 25,000 characters) fold. A fold
  /// hides seven lines or more, never one or two behind a button.
  static const postWholeLines = 18;
  static const postFoldedLines = 12;

  /// The quoted post's text, in a smaller box of its own.
  static const quoteWholeLines = 9;
  static const quoteFoldedLines = 6;

  final String text;

  /// Starts the keys of the text and its button: "x-post" for the linked
  /// post, "x-quote" for the quoted one.
  final String name;

  /// The most lines the text shows without a button.
  final int wholeLines;

  /// The lines a longer text shows while folded.
  final int foldedLines;

  final TextStyle? style;

  /// Opens a link, @mention or #hashtag of the text. Null leaves the text
  /// plain, as in the quoted post, where a tap anywhere opens the quote.
  final void Function(Uri target)? onOpenLink;

  static String get promptXPostShowMore => Intl.message("Show more",
      name: "promptXPostShowMore",
      desc: "Under the text of a long X post in its link preview, which "
          "shows only the first lines: shows all of the text, in place");

  static String get promptXPostShowLess => Intl.message("Show less",
      name: "promptXPostShowLess",
      desc: "Under the whole text of a long X post in its link preview: "
          "cuts it back to its first lines");

  @override
  State<XPostText> createState() => _XPostTextState();
}

class _XPostTextState extends State<XPostText> {
  bool unfolded = false;

  List<XTextLink> _links = const [];
  final List<TapGestureRecognizer> _recognizers = [];

  // The last measurement: laying a long post out twice on every build
  // would cost more than the card's other text together.
  Object? _measured;
  bool _long = false;

  @override
  void initState() {
    super.initState();
    _readLinks();
  }

  @override
  void didUpdateWidget(covariant XPostText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) unfolded = false;
    if (oldWidget.text != widget.text ||
        (oldWidget.onOpenLink == null) != (widget.onOpenLink == null)) {
      _readLinks();
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  void _readLinks() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    _links = widget.onOpenLink == null ? const [] : XPost.linksIn(widget.text);
    for (final link in _links) {
      _recognizers.add(TapGestureRecognizer()
        ..onTap = () => widget.onOpenLink?.call(link.target));
    }
  }

  List<InlineSpan> _spans(Color linkColor) {
    final text = widget.text;
    final spans = <InlineSpan>[];
    var last = 0;
    for (var i = 0; i < _links.length; i++) {
      final link = _links[i];
      spans.add(TextSpan(text: text.substring(last, link.start)));
      spans.add(TextSpan(
        text: text.substring(link.start, link.end),
        style: TextStyle(color: linkColor),
        recognizer: _recognizers[i],
      ));
      last = link.end;
    }
    spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }

  /// Whether the text takes more than [XPostText.wholeLines] lines at
  /// [width], laid out as the [Text] below lays it out.
  bool _isLong(BuildContext context, double width) {
    var style = DefaultTextStyle.of(context).style.merge(widget.style);
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final scaler = MediaQuery.textScalerOf(context);
    final key = (widget.text, width, style, scaler, widget.wholeLines);
    if (_measured == key) return _long;

    // The links only change the text's colour, so the plain text has the
    // same lines.
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      locale: Localizations.maybeLocaleOf(context),
      maxLines: widget.wholeLines,
    )..layout(maxWidth: width);
    _long = painter.didExceedMaxLines;
    painter.dispose();
    _measured = key;
    return _long;
  }

  /// Where the text's first line is on screen ([top]), or the bottom of
  /// its button.
  double? _edge({required bool top}) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(top ? Offset.zero : Offset(0, box.size.height)).dy;
  }

  // What unfolding showed, for folding back: how tall the folded text was,
  // and whether the list around it grew downward (its first line stayed
  // where it was).
  double? _foldedHeight;
  bool _grewDownward = false;

  /// Moves the content of the list around the text [dy] down the screen,
  /// or up when negative, as far as the list goes.
  void _shift(ScrollPosition position, double dy) {
    // Further along a list that grows upward is further up it, which moves
    // its content down the screen.
    final target = position.axisDirection == AxisDirection.up
        ? position.pixels + dy
        : position.pixels - dy;
    position.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  /// Unfolds or folds the text, and keeps the reader's place in the list
  /// around it: unfolding holds the first line where it is, the rest
  /// opening below it, and folding holds the button where it is.
  ///
  /// The chat's timeline grows upward. Left alone, a post unfolded there
  /// pushed its first lines off the top of the view and showed its end.
  /// In a list that grows downward it is folding that needs care: the
  /// button would go up by everything the text loses, past the top of the
  /// view.
  void _toggle() {
    final unfold = !unfolded;
    final box = context.findRenderObject();
    final height = box is RenderBox && box.hasSize ? box.size.height : null;
    final before = _edge(top: unfold);
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;

    if (unfold) {
      _foldedHeight = height;
    } else if (_grewDownward &&
        position != null &&
        height != null &&
        _foldedHeight != null) {
      // Before the text folds, not after: a list drops a post that ends up
      // far above the view, and then nothing is left to put back in place.
      _shift(position, height - _foldedHeight!);
    }
    setState(() => unfolded = unfold);
    if (before == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final after = _edge(top: unfold);
      final position =
          Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
      if (after == null || position == null) return;
      final moved = after - before;
      if (unfold) _grewDownward = moved.abs() < 0.5;
      if (moved.abs() >= 0.5) _shift(position, -moved);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkColor =
        theme.extension<ExtraColors>()?.linkColor ?? theme.colorScheme.primary;

    return LayoutBuilder(builder: (context, constraints) {
      final long = _isLong(context, constraints.maxWidth);
      final folded = long && !unfolded;
      final text = Text.rich(
        TextSpan(children: _spans(linkColor)),
        key: ValueKey('${widget.name}-text'),
        style: widget.style,
        maxLines: folded ? widget.foldedLines : null,
        overflow: folded ? TextOverflow.ellipsis : null,
      );
      if (!long) return text;

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          text,
          Semantics(
            button: true,
            child: InkWell(
              key:
                  ValueKey('${widget.name}-show-${unfolded ? 'less' : 'more'}'),
              onTap: _toggle,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  unfolded
                      ? XPostText.promptXPostShowLess
                      : XPostText.promptXPostShowMore,
                  style: DefaultTextStyle.of(context)
                      .style
                      .merge(widget.style)
                      .copyWith(color: linkColor, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}
