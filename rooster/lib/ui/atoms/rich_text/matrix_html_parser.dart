import 'dart:math';

import 'package:rooster/client/components/emoticon/emoticon.dart';
import 'package:rooster/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/client/matrix/matrix_peer.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/code_block.dart';
import 'package:rooster/ui/atoms/emoji_widget.dart';
import 'package:rooster/ui/atoms/mention.dart';
import 'package:rooster/ui/atoms/rich_text/maths/latex_view.dart';
import 'package:rooster/ui/atoms/rich_text/matrix_html_sanitizer.dart';
import 'package:rooster/ui/atoms/rich_text/spans/link.dart';
import 'package:rooster/utils/emoji/unicode_emoji.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:rooster/utils/matrix_uri/matrix_uri.dart';
import 'package:rooster/utils/text_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:intl/intl.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class MatrixHtmlParser {
  static final RegExp _mxReplyTagPattern = RegExp(
    r'<\s*(/?)\s*mx-reply(?=(?:\s|/?>))[^>]*>',
    caseSensitive: false,
  );

  /// Removes legacy Matrix `<mx-reply>...</mx-reply>` fallback blocks while
  /// preserving the reply body. Malformed or unmatched `<mx-reply>` tags are
  /// stripped without throwing or dropping the remaining text.
  static String stripMxReply(String html) {
    if (html.isEmpty) return html;
    final matches = _mxReplyTagPattern.allMatches(html).toList();
    if (matches.isEmpty) return html;

    final openStack = <(int start, int end)>[];
    final removals = <(int start, int end)>[];

    for (final match in matches) {
      final full = match.group(0)!;
      final isClosing = match.group(1) == '/';
      final isSelfClosing = !isClosing && full.endsWith('/>');

      if (isSelfClosing) {
        removals.add((match.start, match.end));
      } else if (!isClosing) {
        openStack.add((match.start, match.end));
      } else if (openStack.isNotEmpty) {
        final open = openStack.removeLast();
        removals.add((open.$1, match.end));
      } else {
        removals.add((match.start, match.end));
      }
    }

    removals.addAll(openStack);
    removals.sort((a, b) => a.$1.compareTo(b.$1));

    final buffer = StringBuffer();
    var cursor = 0;
    for (final range in removals) {
      if (range.$2 <= cursor) continue;
      if (range.$1 > cursor) {
        buffer.write(html.substring(cursor, range.$1));
      }
      cursor = range.$2;
    }
    if (cursor < html.length) {
      buffer.write(html.substring(cursor));
    }
    return buffer.toString();
  }

  static Widget parse(String text, MatrixClient client, Room? room,
      {bool mentionsRoom = true}) {
    return MatrixHtmlState(
      text,
      client,
      room,
      mentionsRoom: mentionsRoom,
      key: GlobalKey(),
    );
  }
}

class MatrixHtmlState extends StatefulWidget {
  const MatrixHtmlState(this.text, this.client, this.room,
      {this.mentionsRoom = true, super.key});
  final String text;
  final MatrixClient client;
  final Room? room;
  final bool mentionsRoom;

  @override
  State<MatrixHtmlState> createState() => _MatrixHtmlStateState();
}

class _MatrixHtmlStateState extends State<MatrixHtmlState> {
  /// Spoilers the reader has revealed, by element of [_document].
  final Set<dom.Element> revealedSpoilers = {};
  String? _source;
  late dom.Document _document;
  late Map<String, Style> _sanitizedStyles;

  static final CodeBlockHtmlExtension _codeBlock = CodeBlockHtmlExtension();
  static final CodeHtmlExtension _code = CodeHtmlExtension();
  static final LineBreakHtmlExtension _lineBreak = LineBreakHtmlExtension();
  static final MathsHtmlExtension _maths = MathsHtmlExtension();
  static final RoomMentionsHtmlExtension _roomMentions =
      RoomMentionsHtmlExtension();
  static const Set<String> allowedHtmlTags = {
    'body',
    'html',
    'del',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'p',
    'a',
    'ul',
    'ol',
    'sup',
    'sub',
    'li',
    'b',
    'i',
    's',
    'u',
    'strong',
    'em',
    'strike',
    'code',
    'hr',
    'br',
    'div',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    'caption',
    'pre',
    'span',
    'font',
    'img',
    'details',
    'summary',
  };

  void toggleSpoiler(dom.Element spoiler) {
    setState(() {
      if (!revealedSpoilers.remove(spoiler)) revealedSpoilers.add(spoiler);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_source != widget.text) {
      _source = widget.text;
      _document = html_parser.parse(MatrixHtmlParser.stripMxReply(widget.text));
      MatrixHtmlSanitizer.sanitize(_document);
      _sanitizedStyles = MatrixHtmlSanitizer.styles(_document);
      revealedSpoilers.clear();
    }

    final spoiler = SpoilerHtmlExtension(revealedSpoilers, toggleSpoiler);
    final document = _document;
    bool big = shouldDoBigEmoji(document);

    var theme = TextTheme.of(context);
    // Making a new one of these for every message we pass might make a lot of garbage
    var extension =
        MatrixEmoticonHtmlExtension(widget.client, widget.room, big);
    var imageExtension = MatrixImageExtension(widget.client, widget.room);
    var linkify = LinkifyHtmlExtension(widget.client, widget.room, openLink);

    var result = Html.fromDom(
      document: document,
      extensions: [
        _maths,
        extension,
        spoiler,
        _codeBlock,
        _code,
        linkify,
        _lineBreak,
        imageExtension,
        if (widget.mentionsRoom) _roomMentions,
      ],
      style: {
        "body": Style(
          padding: HtmlPaddings.all(0),
          margin: Margins(
            bottom: Margin.zero(),
            left: Margin.zero(),
            top: Margin.zero(),
            right: Margin.zero(),
          ),
          color: Theme.of(context).colorScheme.onSurface,
        ),
        "code": Style(backgroundColor: Colors.black.withAlpha(40)),
        "blockquote": Style(
          border: Border(
              left: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          )),
          padding: HtmlPaddings(
            left: HtmlPadding(4),
          ),
          margin: Margins(
            bottom: Margin(8),
            left: Margin(8),
            top: Margin(8),
            right: Margin.zero(),
          ),
          whiteSpace: WhiteSpace.pre,
        ),
        "h1": Style.fromTextStyle(theme.headlineLarge!).copyWith(
          margin: Margins.all(0),
          padding: HtmlPaddings.all(0),
          color: Theme.of(context).colorScheme.onSurface,
        ),
        "h2": Style.fromTextStyle(theme.headlineMedium!).copyWith(
          margin: Margins.all(0),
          padding: HtmlPaddings.all(0),
          color: Theme.of(context).colorScheme.onSurface,
        ),
        "h3": Style.fromTextStyle(theme.headlineSmall!).copyWith(
          margin: Margins.all(0),
          padding: HtmlPaddings.all(0),
          color: Theme.of(context).colorScheme.onSurface,
        ),
        "ul": Style(
          margin: Margins.all(2),
          padding: HtmlPaddings.all(2),
        ),
        "li": Style(
          margin: Margins.all(0),
          padding: HtmlPaddings.all(0),
        ),
        "p": Style(
          margin: Margins.all(0),
          padding: HtmlPaddings.all(0),
        ),
        ..._sanitizedStyles,
      },
      onLinkTap: (url, attributes, element) {
        final uri = MatrixHtmlLinks.resolve(url ?? '');
        if (uri != null) LinkUtils.open(uri, context: context);
      },
      onlyRenderTheseTags: allowedHtmlTags,
    );

    return result;
  }

  openLink(Uri uri) {
    LinkUtils.open(uri,
        clientId: widget.client.identifier,
        context: context,
        contextRoomId: widget.room?.identifier);
  }
}

bool shouldDoBigEmoji(dom.Document document) {
  if (document.body == null) return false;

  for (var node in document.body!.nodes) {
    if (node is dom.Text) {
      for (var char in node.text.characters) {
        if (char.trim() == "") continue;

        if (TextUtils.isEmoji(char)) continue;

        return false;
      }
    } else if (node is dom.Element &&
        !node.attributes.containsKey("data-mx-emoticon")) {
      return false;
    }
  }

  return true;
}

class MatrixEmoticonHtmlExtension extends HtmlExtension {
  final MatrixClient client;
  final Room? room;
  final bool bigEmoji;
  const MatrixEmoticonHtmlExtension(this.client, this.room, this.bigEmoji);

  double get emojiSize => bigEmoji ? 48 : 20;

  @override
  InlineSpan build(ExtensionContext context) {
    Uri? uri;

    if (context.node is dom.Text) {
      var spans = List<InlineSpan>.empty(growable: true);

      for (var char in context.node.text!.characters) {
        if (char.trim() == "") {
          spans.add(TextSpan(
            text: char,
          ));
        } else {
          spans.add(WidgetSpan(
              child: EmojiWidget(
            UnicodeEmoticon(char),
            height: emojiSize,
          )));
        }
      }

      return TextSpan(children: spans);
    }

    if (context.attributes.containsKey("src")) {
      uri = Uri.parse(context.attributes["src"]!);
    }

    if (uri == null) {
      return TextSpan(text: context.attributes["alt"] ?? "");
    }

    var size = emojiSize;

    var fontSize = context.style?.fontSize?.value;
    if (fontSize != null) {
      fontSize = fontSize * 1.2;
      size = max(size, fontSize);
    }

    if (room?.shouldPreviewMedia == false) {
      return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Tooltip(
              padding: const EdgeInsets.all(0),
              decoration: const BoxDecoration(
                color: Colors.transparent,
              ),
              richMessage: WidgetSpan(
                  child: EmojiWidget(
                MatrixEmoticon(uri, client.matrixClient,
                    shortcode: context.attributes["alt"] ?? "",
                    packUsage: EmoticonUsage.all,
                    usage: EmoticonUsage.emoji),
                height: 48,
              )),
              child: tiamat.Text.labelLow(context.attributes["alt"] ?? "")));
    }

    return WidgetSpan(
        child: Tooltip(
      message: context.attributes["alt"] ?? "",
      child: EmojiWidget(
        MatrixEmoticon(uri, client.matrixClient,
            shortcode: context.attributes["alt"] ?? "",
            packUsage: EmoticonUsage.all,
            usage: EmoticonUsage.emoji),
        height: size,
      ),
    ));
  }

  @override
  bool matches(ExtensionContext context) {
    // If text contains only emojis and spaces we can handle this too
    if (context.node is dom.Text) {
      if (context.node.text == null) return false;
      if (context.node.text!.trim().isEmpty) return false;

      for (var char in context.node.text!.characters) {
        if (char.trim() == "") continue;

        if (TextUtils.isEmoji(char)) continue;

        return false;
      }

      return true;
    }

    return context.attributes.containsKey("data-mx-emoticon");
  }

  static const Set<String> tags = {"img"};

  @override
  Set<String> get supportedTags => tags;
}

class CodeBlockHtmlExtension extends HtmlExtension {
  @override
  InlineSpan build(ExtensionContext context) {
    var element = context.element!.children.firstOrNull;
    element ??= context.element;

    var langauge = element?.className.replaceAll('language-', '');
    var code = element!.text;
    return WidgetSpan(
        child: ExpandableCodeBlock(
      text: code,
      language: langauge,
    ));
  }

  static const Set<String> tags = {"pre"};

  @override
  Set<String> get supportedTags => tags;
}

class LineBreakHtmlExtension extends HtmlExtension {
  @override
  InlineSpan build(ExtensionContext context) {
    var result =
        context.parser.buildFromExtension(context, extensionsToIgnore: {this});

    if (context.node is! dom.Element) {
      return result;
    }

    return TextSpan(children: [
      if (context.element?.previousElementSibling != null)
        const TextSpan(text: "\n"),
      result,
      if (context.element?.nextElementSibling != null)
        const TextSpan(text: "\n"),
    ]);
  }

  static const Set<String> tags = {"p"};

  @override
  Set<String> get supportedTags => tags;
}

class CodeHtmlExtension extends HtmlExtension {
  @override
  InlineSpan build(ExtensionContext context) {
    var color = Theme.of(context.buildContext!)
            .extension<ExtraColors>()
            ?.codeHighlight ??
        Theme.of(context.buildContext!).primaryColor;

    return TextSpan(
        text: context.node.text,
        style: TextStyle(
            fontFamily: "Code",
            color: color,
            fontFeatures: const [FontFeature.disable("calt")]));
  }

  static const Set<String> tags = {"code"};

  @override
  Set<String> get supportedTags => tags;
}

class LinkifyHtmlExtension extends HtmlExtension {
  final Room? room;
  final MatrixClient client;
  final Function(Uri uri) openLink;
  const LinkifyHtmlExtension(this.client, this.room, this.openLink);

  @override
  InlineSpan build(ExtensionContext context) {
    final resolved =
        MatrixHtmlLinks.resolve(context.node.attributes["href"] ?? '');
    if (resolved != null) {
      final href = resolved;
      final uri = href.toString();

      if (href.host == "matrix.to") {
        var result = MatrixClient.parseMatrixLink(href);
        if (result != null) {
          var mxid = result.$2;

          Widget? overrideWidget;
          if (room != null) {
            if (result.$1 == MatrixLinkType.user) {
              var user = room!.getMemberOrFallback(mxid);
              overrideWidget = MentionWidget(
                displayName: user.displayName,
                placeholderColor: user.defaultColor,
                avatar: user.avatar,
                onTap: () => openLink(href),
              );
            }
          }

          if (result.$1 == MatrixLinkType.room ||
              result.$1 == MatrixLinkType.roomAlias) {
            var mentionedRoom = client.getRoom(mxid);
            mentionedRoom ??= client.getRoomByAlias(mxid);

            var vias = client.parseAddressToIdAndVia(uri);

            overrideWidget = MentionWidget(
              displayName: mentionedRoom?.displayName ?? mxid.substring(1),
              vias: vias?.$2,
              fallbackIcon: preferences.usePlaceholderRoomAvatars.value
                  ? null
                  : mentionedRoom?.icon ?? Icons.tag,
              placeholderColor:
                  mentionedRoom?.defaultColor ?? MatrixPeer.hashColor(mxid),
              avatar: mentionedRoom?.avatar,
              onTap: () => LinkUtils.open(href,
                  clientId: client.identifier, contextRoomId: room?.identifier),
            );
          }

          if (overrideWidget != null) {
            return WidgetSpan(
                child: Transform.translate(
                    offset: Offset(0, 2),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
                      child: overrideWidget,
                    )));
          }
        }
      }

      return LinkSpan.create(context.node.text!,
          clientId: client.identifier,
          context: context.buildContext!,
          destination: href);
    }

    return TextSpan(
        children: TextUtils.linkifyString(context.node.text!,
            clientId: client.identifier, context: context.buildContext!));
  }

  @override
  bool matches(ExtensionContext context) {
    if (MatrixHtmlLinks.resolve(context.node.attributes["href"] ?? '') !=
        null) {
      return true;
    }

    return context.node is dom.Text &&
        TextUtils.containsUrl(context.node.text!);
  }

  @override
  Set<String> get supportedTags => {};
}

class SpoilerHtmlExtension extends HtmlExtension {
  final Set<dom.Element> revealed;
  final void Function(dom.Element spoiler) onTap;

  SpoilerHtmlExtension(this.revealed, this.onTap);

  static String labelSpoilerReason(String reason) =>
      Intl.message("Spoiler: $reason",
          name: "labelSpoilerReason",
          args: [reason],
          desc: "Shown before a hidden spoiler in a message, with the reason "
              "its sender gave for hiding it");

  static String get labelSpoilerHidden =>
      Intl.message("Hidden spoiler, tap to reveal",
          name: "labelSpoilerHidden",
          desc: "Read by screen readers in place of the hidden text of a "
              "spoiler in a message");

  @override
  InlineSpan build(ExtensionContext context) {
    final element = context.element!;
    final hidden = !revealed.contains(element);
    final reason = element.attributes["data-mx-spoiler"]?.trim() ?? "";
    final color = Theme.of(context.buildContext!).colorScheme.onSurface;

    final recogniser = TapGestureRecognizer()..onTap = () => onTap(element);
    final body = TextSpan(
        text: context.node.text,
        recognizer: recogniser,
        semanticsLabel: hidden ? labelSpoilerHidden : null,
        style: TextStyle(
            color: color,
            backgroundColor: hidden ? color : color.withAlpha(20)));

    if (!hidden || reason.isEmpty) return body;

    return TextSpan(children: [
      TextSpan(
          text: "${labelSpoilerReason(reason)} ",
          recognizer: recogniser,
          style: TextStyle(
              color: color.withAlpha(180), fontStyle: FontStyle.italic)),
      body,
    ]);
  }

  @override
  bool matches(ExtensionContext context) {
    return context.element != null &&
        context.attributes.containsKey("data-mx-spoiler");
  }

  @override
  Set<String> get supportedTags => {};
}

/// Renders `data-mx-maths` (Matrix v1.11) on `<span>` (inline) and `<div>`
/// (block). The element's own content is the fallback for clients without
/// maths, so it is not shown.
class MathsHtmlExtension extends HtmlExtension {
  static const attribute = "data-mx-maths";

  @override
  InlineSpan build(ExtensionContext context) {
    final element = context.element!;
    final display = element.localName == "div";
    final style = TextStyle(
      fontSize: context.style?.fontSize?.value,
      color: context.style?.color,
    );

    final view = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: LatexView(element.attributes[attribute]!,
          display: display, style: style),
    );
    final span =
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: view);
    if (!display) return span;

    final siblings = element.parentNode?.nodes ?? const <dom.Node>[];
    final index = siblings.indexOf(element);
    bool shown(dom.Node node) =>
        node is dom.Element || (node.text?.trim().isNotEmpty ?? false);

    return TextSpan(children: [
      if (siblings.take(index).any(shown)) const TextSpan(text: "\n"),
      span,
      if (siblings.skip(index + 1).any(shown)) const TextSpan(text: "\n"),
    ]);
  }

  @override
  bool matches(ExtensionContext context) {
    final element = context.element;
    return element != null &&
        (element.localName == "span" || element.localName == "div") &&
        element.attributes.containsKey(attribute);
  }

  @override
  Set<String> get supportedTags => {};
}

/// Where a link in a message goes. `matrix:` URIs become the matrix.to link
/// the app opens; links the sanitiser does not allow give null.
class MatrixHtmlLinks {
  static Uri? resolve(String href) {
    if (href.trim().isEmpty || !MatrixHtmlSanitizer.isAllowedHref(href)) {
      return null;
    }
    final matrixUri = MatrixUri.tryParse(href);
    if (matrixUri != null) return matrixUri.toMatrixToUri();
    return Uri.tryParse(href.trim());
  }
}

class RoomMentionsHtmlExtension extends HtmlExtension {
  RoomMentionsHtmlExtension();

  @override
  InlineSpan build(ExtensionContext context) {
    var data = (context.node as dom.Text).data;
    return TextSpan(
        children: TextUtils.formatMatches(
      MatrixRoom.roomMentionRegex.allMatches(data),
      data,
      builder: (matchedText, theme) {
        return WidgetSpan(
            child: Transform.translate(
                offset: Offset(0, 2),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
                  child: MentionWidget(
                      displayName: matchedText,
                      showAvatar: false,
                      placeholderColor:
                          ColorScheme.of(context.buildContext!).primary),
                )));
      },
    ));
  }

  @override
  bool matches(ExtensionContext context) {
    if (context.node case dom.Text text) {
      return MatrixRoom.roomMentionRegex.hasMatch(text.data);
    }

    return false;
  }

  @override
  Set<String> get supportedTags => {};
}

class MatrixImageExtension extends HtmlExtension {
  final double defaultDimension;

  final MatrixClient client;
  final Room? room;
  const MatrixImageExtension(this.client, this.room,
      {this.defaultDimension = 64});

  @override
  Set<String> get supportedTags => {'img'};

  @override
  InlineSpan build(ExtensionContext context) {
    final mxcUrl = Uri.tryParse(context.attributes['src'] ?? '');

    if (mxcUrl == null) {
      return TextSpan(text: context.attributes['alt']);
    }

    if (mxcUrl.scheme != 'mxc' || room?.shouldPreviewMedia == false) {
      return LinkSpan.create(mxcUrl.toString(),
          clientId: client.identifier,
          destination: mxcUrl,
          context: context.buildContext!);
    }

    final width = double.tryParse(context.attributes['width'] ?? '');
    final height = double.tryParse(context.attributes['height'] ?? '');

    return WidgetSpan(
      child: SizedBox(
          width: width ?? height ?? defaultDimension,
          height: height ?? width ?? defaultDimension,
          child: Image(
            image: MatrixMxcImage(
              mxcUrl,
              client.matrixClient,
            ),
          )),
    );
  }
}
