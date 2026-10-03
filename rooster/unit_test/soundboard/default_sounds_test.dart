import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/soundboard/default_sounds.dart';
import 'package:rooster/ui/organisms/soundboard/soundboard_call_controller.dart';

class _Client implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every default sound loads from the app bundle', () async {
    final sounds = defaultSoundboardCatalog.sounds;
    expect(sounds, hasLength(6));
    for (final sound in sounds) {
      final bytes = await SoundboardCallController.loadBytes(_Client(), sound);
      // MP3: an ID3 tag or a frame sync.
      expect(bytes.isNotEmpty && (bytes[0] == 0x49 || bytes[0] == 0xFF), isTrue,
          reason: sound.mediaUri);
    }
    await rootBundle.loadString('assets/soundboard/CREDITS.md');
  });
}
