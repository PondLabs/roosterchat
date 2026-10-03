import 'dart:typed_data';

import 'package:rooster/client/components/dj/dj_engine.dart';
import 'package:rooster/client/components/dj/dj_models.dart';
import 'package:rooster/client/components/dj/dj_session.dart';
import 'package:rooster/client/matrix/components/dj/dj_platform.dart';
import 'package:rooster/client/matrix/components/dj/web/web_dj_engine.dart';
import 'package:rooster/client/matrix/components/dj/web/web_dj_files.dart';
import 'package:rooster/client/matrix/components/dj/web/web_dj_link_resolver.dart';
import 'package:rooster/main.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

DjPlatform createDjPlatform() => _WebDjPlatform();

/// The browser: DJs the DJ's own files and direct links to audio files.
/// Songs from source extensions need the desktop app.
class _WebDjPlatform implements DjPlatform {
  @override
  String get name => 'web';

  @override
  bool get canDj => true;

  @override
  DjEngineFactory? engineFactory(lk.Room room) =>
      () => WebDjEngine(room, monitorVolume: preferences.djMusicVolume.value);

  @override
  late final DjResolver? resolver = WebDjLinkResolver();

  @override
  DjSources? get sources => null;

  /// A browser gives no paths.
  @override
  Future<List<DjTrack>> localTracks(List<String> paths,
          {required String addedBy, required String Function() newId}) async =>
      const [];

  @override
  Future<List<DjTrack>> pickedTracks(
          List<({String name, Uint8List bytes})> files,
          {required String addedBy,
          required String Function() newId}) async =>
      [
        for (final file in files)
          WebDjFiles.instance
              .track(file.name, file.bytes, id: newId(), addedBy: addedBy),
      ];
}
