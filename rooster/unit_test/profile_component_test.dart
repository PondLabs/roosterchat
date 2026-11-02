import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';

void main() {
  group('pronouns', () {
    test('are stored as one trimmed entry in the given language', () {
      expect(
        MatrixProfileComponent.pronounsContent('  ela/dela ', 'pt-BR'),
        [
          {'language': 'pt-BR', 'summary': 'ela/dela'},
        ],
      );
    });

    test('null or blank means none', () {
      expect(MatrixProfileComponent.pronounsContent(null, 'en'), isNull);
      expect(MatrixProfileComponent.pronounsContent('   ', 'en'), isNull);
    });
  });

  group('card color scheme', () {
    test('with a brightness forces the card light or dark', () {
      expect(
        MatrixProfileComponent.colorSchemeContent(
          const Color(0xFF12AB34),
          Brightness.dark,
        ),
        {'color': '#12ab34', 'brightness': 'dark'},
      );
      expect(
        MatrixProfileComponent.colorSchemeContent(
          const Color(0xFF12AB34),
          Brightness.light,
        ),
        {'color': '#12ab34', 'brightness': 'light'},
      );
    });

    test('without one leaves the key out, so the card follows the viewer', () {
      expect(
        MatrixProfileComponent.colorSchemeContent(
          const Color(0xFF12AB34),
          null,
        ),
        {'color': '#12ab34'},
      );
    });
  });

  test('a badge that does not parse is skipped', () async {
    // Cleared account data is `{}`: no signatures at all.
    expect(
      await MatrixProfile.badgeFromContent(_NoClient(), '@me:example.org', {}),
      isNull,
    );
  });
}

class _NoClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
