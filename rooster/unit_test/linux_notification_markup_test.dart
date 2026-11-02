// The body of a Linux notification is markup, and the server only draws
// the parts of it that it lists. GNOME Shell lists body-markup and nothing
// more, and showed a mention as `<a href="https://matrix.to/#/@…`.
import 'package:rooster/client/components/push_notification/modifiers/linux_notification_formatting.dart';
import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:rooster/main.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String> render(
  String body, {
  bool hyperlinks = false,
  Future<Uri?> Function(String src)? image,
  Future<NotificationLinkPreview?> Function(Uri uri)? preview,
}) =>
    NotificationMarkup(
      hyperlinks: hyperlinks,
      mention: (uri) => uri.fragment == '/@ana:example.org' ? '@Ana' : null,
      image: image,
      preview: preview,
    ).render(HtmlParser(body).parse());

/// What `gnome-shell` 50 answers to GetCapabilities.
LinuxServerCapabilities gnome({bool markup = true}) => LinuxServerCapabilities(
      otherCapabilities: const {},
      body: true,
      bodyHyperlinks: false,
      bodyImages: false,
      bodyMarkup: markup,
      iconMulti: false,
      iconStatic: true,
      persistence: true,
      sound: true,
      actions: true,
      actionIcons: false,
    );

MessageNotificationContent message(String content) =>
    MessageNotificationContent(
      senderName: "Ana",
      senderId: "@ana:example.org",
      roomName: "general",
      content: content,
      eventId: r"$one",
      roomId: "!general:example.org",
      clientId: "client-1",
      isDirectMessage: false,
    );

void main() {
  group('the markup', () {
    test('a mention is the name, in bold, not a link', () async {
      expect(
          await render('<a href="https://matrix.to/#/@ana:example.org">ana</a>'
              ': look at this'),
          '<b>@Ana</b>: look at this');
    });

    test('a link is its text where the server draws no links', () async {
      expect(
          await render('see <a href="https://example.org/a?b=1&amp;c=2">'
              'https://example.org/a?b=1&amp;c=2</a>'),
          'see https://example.org/a?b=1&amp;c=2');
    });

    test('a link is a link where the server draws them', () async {
      expect(
          await render('<a href="http://example.org/">the page</a>',
              hyperlinks: true),
          '<a href="http://example.org/">the page</a>');
    });

    test('a preview takes the place of a bare address', () async {
      expect(
          await render(
              '<a href="https://example.org/x">https://example.org/x</a>',
              preview: (_) async => (title: 'Fish & chips', image: null)),
          '<i>"Fish &amp; chips"</i> <i>(example.org)</i>');
      expect(
          await render('<a href="https://example.org/x">this</a>',
              preview: (_) async =>
                  (title: 'Page', image: Uri.file('/tmp/p.png'))),
          'this <i>"Page"</i> <i>(example.org)</i>\n'
          '<img src="file:///tmp/p.png"/>');
    });

    test('text that looks like markup is escaped', () async {
      expect(await render('a &lt;b&gt; &amp; c'), 'a &lt;b&gt; &amp; c');
      expect(await render('<b>1 &lt; 2</b>'), '<b>1 &lt; 2</b>');
    });

    test('an emoji is its name unless the server draws images', () async {
      const emoji = '<img data-mx-emoticon src="mxc://x/cat" alt=":cat:">';
      expect(await render(emoji), '<i>:cat:</i>');
      expect(
          await render(emoji, image: (src) async => Uri.file('/tmp/cat 1.png')),
          '<img src="file:///tmp/cat%201.png" alt=":cat:"/>');
    });

    test('the reply quote goes, lines stay apart', () async {
      expect(
          await render('<mx-reply><blockquote>old</blockquote></mx-reply>'
              '<p>one</p><p>two<br>three</p>'),
          'one\ntwo\nthree');
    });
  });

  group('the modifier', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
    });

    test('a plain body is escaped for a server that reads markup', () async {
      final content =
          await NotificationModifierLinuxFormatting(capabilities: () => gnome())
              .process(message('I <3 R&B'));

      expect(content!.content, 'I &lt;3 R&amp;B');
    });

    test('a server that reads no markup gets the plain body as it is',
        () async {
      final content = await NotificationModifierLinuxFormatting(
              capabilities: () => gnome(markup: false))
          .process(message('I <3 R&B'));

      expect(content!.content, 'I <3 R&B');
    });
  });
}
