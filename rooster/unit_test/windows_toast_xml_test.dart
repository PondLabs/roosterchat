import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:rooster/client/components/push_notification/windows/windows_notifier.dart';

/// Markup in [xml] with every entity taken out: what is left of "&" or "<"
/// would break the XML, and Windows drops a toast it cannot parse.
String _withoutEntities(String xml) =>
    xml.replaceAll(RegExp(r'&(amp|lt|gt|quot|apos);'), '');

void main() {
  test('a message with "&" and "<" in it still makes a valid toast', () {
    final xml = WindowsNotifier.messageToastXml(
      MessageNotificationContent(
        senderName: 'Tom & Jerry',
        senderId: '@tom:example.org',
        roomName: 'R&D <team>',
        content: 'look <3 https://example.org/?a=1&b=2',
        eventId: r'$event',
        roomId: '!room:example.org',
        clientId: 'client-1',
        isDirectMessage: false,
      ),
      r'C:\Users\me\avatar.png',
    );

    expect(xml, contains('<text>Tom &amp; Jerry</text>'));
    expect(xml,
        contains('<text>look &lt;3 https://example.org/?a=1&amp;b=2</text>'));
    expect(xml, contains('title="R&amp;D &lt;team&gt;"'));
    expect(_withoutEntities(xml), isNot(contains('&')));
    expect(_withoutEntities(xml), isNot(contains('<3')));
  });

  test('a call from a room with "&" in its name still makes a valid toast', () {
    final xml = WindowsNotifier.callToastXml(
      CallNotificationContent(
        roomId: '!room:example.org',
        senderId: '@tom:example.org',
        senderName: 'Tom',
        roomName: 'Tom & Jerry',
        clientId: 'client-1',
        callId: 'call-1',
        isDirectMessage: false,
        title: 'Tom & Jerry',
        content: 'Tom <is> calling',
      ),
      '',
    );

    expect(xml, contains('<text>Tom &amp; Jerry</text>'));
    expect(xml, contains('<text>Tom &lt;is&gt; calling</text>'));
    expect(_withoutEntities(xml), isNot(contains('&')));
  });
}
