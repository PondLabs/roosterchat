import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/components/space_component.dart';
import 'package:flutter/material.dart';

abstract class SpaceColorSchemeComponent<R extends Client, T extends Space>
    implements SpaceComponent<R, T> {
  ColorScheme get scheme;
}
