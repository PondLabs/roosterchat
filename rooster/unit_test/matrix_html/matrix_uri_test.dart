import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/utils/matrix_uri/matrix_uri.dart';

void main() {
  group('MatrixUri.tryParse', () {
    test('parses a user with an action', () {
      final uri = MatrixUri.tryParse('matrix:u/alice:example.org?action=chat')!;
      expect(uri.kind, MatrixUriKind.user);
      expect(uri.identifier, '@alice:example.org');
      expect(uri.eventId, isNull);
      expect(uri.action, MatrixUriAction.chat);
    });

    test('parses a room alias with join action', () {
      final uri =
          MatrixUri.tryParse('matrix:r/somewhere:example.org?action=join')!;
      expect(uri.kind, MatrixUriKind.roomAlias);
      expect(uri.identifier, '#somewhere:example.org');
      expect(uri.action, MatrixUriAction.join);
    });

    test('parses a room id with an event and several via servers', () {
      final uri = MatrixUri.tryParse('matrix:roomid/somewhere:example.org'
          '/e/event?via=elsewhere.ca&via=other.org:8448')!;
      expect(uri.kind, MatrixUriKind.roomId);
      expect(uri.identifier, '!somewhere:example.org');
      expect(uri.eventId, r'$event');
      expect(uri.via, ['elsewhere.ca', 'other.org:8448']);
      expect(uri.action, isNull);
    });

    test('decodes percent-encoding in identifiers and queries', () {
      final uri = MatrixUri.tryParse(
          'matrix:roomid/abc%2Fdef%3Aexample.org/e/a%2Bb%2Fc?via=ex%2Eorg')!;
      expect(uri.identifier, '!abc/def:example.org');
      expect(uri.eventId, r'$a+b/c');
      expect(uri.via, ['ex.org']);
    });

    test('ignores the authority, the fragment and unknown actions', () {
      final uri = MatrixUri.tryParse(
          'MATRIX://example.org/u/bob:example.org?action=dance#frag')!;
      expect(uri.identifier, '@bob:example.org');
      expect(uri.action, isNull);
    });

    test('rejects dangerous and foreign schemes', () {
      for (final input in [
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'https://matrix.to/#/@alice:example.org',
        'matrixx:u/alice:example.org',
        'vbscript:msgbox',
      ]) {
        expect(MatrixUri.tryParse(input), isNull, reason: input);
      }
    });

    test('rejects URIs that break the grammar', () {
      for (final input in [
        'matrix:',
        'matrix:u',
        'matrix:u/',
        'matrix:x/alice:example.org',
        'matrix:u/alice',
        'matrix:u/:example.org',
        'matrix:u/alice:example.org/e/event',
        'matrix:r/room:example.org/x/event',
        'matrix:r/room:example.org/e/',
        'matrix:roomid/room:example.org/e/a/b',
        'matrix:u/alice:exa mple.org',
        'matrix:u/alice:example.org?via=bad/server',
        'matrix:u/alice%ZZ:example.org',
        'matrix://example.org',
      ]) {
        expect(MatrixUri.tryParse(input), isNull, reason: input);
      }
    });
  });

  group('MatrixUri generator', () {
    test('writes canonical URIs that parse back', () {
      final uri = MatrixUri.fromIdentifier('!abc/def:example.org',
          eventId: r'$a+b/c',
          via: ['one.org', 'two.org'],
          action: MatrixUriAction.join)!;
      final text = uri.toString();
      expect(
          text,
          'matrix:roomid/abc%2Fdef:example.org/e/a%2Bb%2Fc'
          '?via=one.org&via=two.org&action=join');
      expect(MatrixUri.tryParse(text), uri);
      expect(MatrixUri.fromIdentifier('@alice:example.org').toString(),
          'matrix:u/alice:example.org');
      expect(MatrixUri.fromIdentifier('#room:example.org').toString(),
          'matrix:r/room:example.org');
    });

    test('refuses identifiers it cannot represent', () {
      expect(MatrixUri.fromIdentifier(''), isNull);
      expect(MatrixUri.fromIdentifier('alice:example.org'), isNull);
      expect(MatrixUri.fromIdentifier('@alice'), isNull);
      expect(MatrixUri.fromIdentifier('@alice:example.org', eventId: r'$e'),
          isNull);
      expect(MatrixUri.fromIdentifier('!r:example.org', eventId: 'e'), isNull);
      expect(MatrixUri.fromIdentifier('!r:example.org', via: ['a b']), isNull);
    });

    test('converts to the matrix.to link the app already opens', () {
      final room = MatrixUri.tryParse(
          'matrix:roomid/room:example.org/e/event?via=a.org&via=b.org')!;
      final link = MatrixClient.parseMatrixLink(room.toMatrixToUri())!;
      expect(link.$1, MatrixLinkType.room);
      expect(link.$3, r'!room:example.org/$event?via=a.org&via=b.org');

      final user = MatrixUri.tryParse('matrix:u/alice:example.org')!;
      expect(MatrixClient.parseMatrixLink(user.toMatrixToUri())!.$1,
          MatrixLinkType.user);

      final alias = MatrixUri.tryParse('matrix:r/room:example.org')!;
      final aliasLink = MatrixClient.parseMatrixLink(alias.toMatrixToUri())!;
      expect(aliasLink.$1, MatrixLinkType.roomAlias);
      expect(aliasLink.$2, '#room:example.org');
    });
  });
}
