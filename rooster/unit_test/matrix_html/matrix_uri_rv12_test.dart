// Regression test for c1-1: matrix:roomid/ must accept room version 12 room
// ids (Matrix v1.16, MSC4291), which have no server name. Place it in
// rooster/unit_test/matrix_html/ (for example matrix_uri_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:rooster/utils/matrix_uri/matrix_uri.dart';

void main() {
  group('matrix: room version 12 ids', () {
    const v12 = '!31hneApxJ_1o-63DmFrpeqnkFfWppnzWso1JvH3ogLM';

    test('roomid/ of a room version 12 room parses', () {
      final uri = MatrixUri.tryParse(
          'matrix:roomid/${v12.substring(1)}?via=example.org');
      expect(uri, isNotNull);
      expect(uri!.identifier, v12);
      expect(uri.via, ['example.org']);
    });

    test('generator accepts a room version 12 room id', () {
      final uri = MatrixUri.fromIdentifier(v12, via: ['example.org']);
      expect(uri, isNotNull);
      expect(MatrixUri.tryParse(uri.toString()), uri);
    });

    test('a link to an event in a room version 12 room stays a link', () {
      expect(
          MatrixHtmlLinks.resolve(
              'matrix:roomid/${v12.substring(1)}/e/abc?via=example.org'),
          isNotNull);
    });

    test('users and aliases still need a server name', () {
      expect(MatrixUri.tryParse('matrix:u/alice'), isNull);
      expect(MatrixUri.tryParse('matrix:r/room'), isNull);
    });
  });
}
