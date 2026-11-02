import 'package:rooster/client/components/user_color/user_color_component.dart';
import 'package:flutter/painting.dart';

/// The name colors Settings > Profile offers, one hue each. The dark theme
/// variants have an HSL lightness of 0.78, so tiamat's Text.adjustColor leaves
/// them as they are, and the light ones are dark enough to read on the light
/// theme's chat and member list. unit_test/name_color_palette_test.dart holds
/// them to that.
const namePalette = <NameColor>[
  NameColor(onDark: Color(0xFFF79797), onLight: Color(0xFFC41C1C)),
  NameColor(onDark: Color(0xFFF7BF97), onLight: Color(0xFF9C4E16)),
  NameColor(onDark: Color(0xFFF7DF97), onLight: Color(0xFF785F11)),
  NameColor(onDark: Color(0xFFD7F797), onLight: Color(0xFF4C6B0F)),
  NameColor(onDark: Color(0xFF97F7B7), onLight: Color(0xFF117432)),
  NameColor(onDark: Color(0xFF97F7E7), onLight: Color(0xFF107060)),
  NameColor(onDark: Color(0xFF97DFF7), onLight: Color(0xFF136986)),
  NameColor(onDark: Color(0xFF97BFF7), onLight: Color(0xFF1B60C0)),
  NameColor(onDark: Color(0xFF9797F7), onLight: Color(0xFF4C4CE6)),
  NameColor(onDark: Color(0xFFBF97F7), onLight: Color(0xFF7E36E2)),
  NameColor(onDark: Color(0xFFE797F7), onLight: Color(0xFFA41BC0)),
  NameColor(onDark: Color(0xFFF797C7), onLight: Color(0xFFBB1B6B)),
];
