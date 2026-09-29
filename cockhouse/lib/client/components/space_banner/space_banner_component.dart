import 'dart:typed_data';

import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/components/space_component.dart';
import 'package:flutter/widgets.dart';

abstract class SpaceBannerComponent<R extends Client, T extends Space>
    implements SpaceComponent<R, T> {
  ImageProvider? get banner;

  bool get canEditBanner;

  Future<void> setBanner(Uint8List data, {String? mimeType});
  Future<void> removeBanner();
}
