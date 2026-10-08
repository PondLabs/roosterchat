import 'package:rooster/client/components/space_color_scheme/space_color_scheme_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_space.dart';
import 'package:rooster/utils/image/lod_image.dart';
import 'package:rooster/utils/task_scheduler.dart';
import 'package:rooster/debug/log.dart';
import 'package:flutter/material.dart';

class MatrixSpaceColorSchemeComponent
    implements SpaceColorSchemeComponent<MatrixClient, MatrixSpace> {
  @override
  MatrixClient client;

  @override
  ColorScheme get scheme => _scheme;

  @override
  MatrixSpace space;

  static TaskScheduler scheduler = OneAtATimeScheduler();

  MatrixSpaceColorSchemeComponent(this.client, this.space) {
    _scheme = ColorScheme.fromSeed(seedColor: space.color);

    _schedule();

    space.onUpdate.listen((_) {
      _schedule();
    });
  }

  late ColorScheme _scheme;

  /// The avatar the scheme was last taken from, so a space update that did
  /// not change it (a message in one of its rooms, every sync) costs
  /// nothing: decoding the avatar and quantising its colours is a few
  /// hundred milliseconds on the UI isolate per space.
  ImageProvider? _schemeFrom;
  bool _queued = false;

  void _schedule() {
    if (_queued || space.avatar == null || space.avatar == _schemeFrom) return;
    _queued = true;
    MatrixSpaceColorSchemeComponent.scheduler.enqueue(() async {
      _queued = false;
      await updateColorScheme();
    });
  }

  Future<void> updateColorScheme() async {
    final avatar = space.avatar;
    if (avatar == null || avatar == _schemeFrom) return;
    try {
      if (avatar case LODImageProvider img) {
        await img.fetchThumbnail();
      }

      var scheme = await ColorScheme.fromImageProvider(
          provider: avatar,
          dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot);

      _scheme = scheme;
      _schemeFrom = avatar;
    } catch (e, s) {
      // The seed colour stays; the avatar is tried again when it changes.
      _schemeFrom = avatar;
      Log.onError(e, s,
          content: "Could not take a colour scheme from the space avatar");
    }
  }
}
