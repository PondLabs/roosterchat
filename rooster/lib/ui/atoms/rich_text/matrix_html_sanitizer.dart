import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:rooster/utils/matrix_uri/matrix_uri.dart';

/// Normalises the attributes of `org.matrix.custom.html` that the renderer
/// reads, so that only values the specification allows reach flutter_html.
class MatrixHtmlSanitizer {
  static const colorAttributes = ['data-mx-color', 'data-mx-bg-color'];

  /// Link schemes the specification lets `<a href>` use, plus `matrix:`.
  static const allowedLinkSchemes = {
    'http',
    'https',
    'ftp',
    'mailto',
    'magnet',
    MatrixUri.scheme,
  };

  static final RegExp _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');
  static final RegExp _integer = RegExp(r'^[+-]?[0-9]{1,9}$');

  /// Returns the colour as lowercase `#rrggbb`, or null when it is anything
  /// other than a six digit hex colour (named colours, `javascript:`, CSS).
  static String? sanitizeColor(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return _hexColor.hasMatch(trimmed) ? trimmed.toLowerCase() : null;
  }

  /// The first number of an `<ol start="N">` list. Zero and negative numbers
  /// are valid (Matrix v1.18); anything that is not an integer gives null, so
  /// the list starts at 1.
  static int? parseListStart(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (!_integer.hasMatch(trimmed)) return null;
    return int.parse(trimmed);
  }

  /// Whether a link with this `href` may be shown and opened.
  static bool isAllowedHref(String href) {
    final uri = Uri.tryParse(href.trim());
    if (uri == null || !uri.hasScheme) return false;
    if (!allowedLinkSchemes.contains(uri.scheme.toLowerCase())) return false;
    if (uri.scheme.toLowerCase() == MatrixUri.scheme) {
      return MatrixUri.tryParse(href) != null;
    }
    return true;
  }

  /// Rewrites [document] in place: `<style>`, `<script>` and `<iframe>`
  /// elements, inline `style` attributes, and invalid colours, list starts
  /// and links are removed, and `<font>` keeps only the attributes Matrix
  /// allows.
  static void sanitize(dom.Document document) {
    for (final element in document.querySelectorAll('style, script, iframe')) {
      element.remove();
    }

    for (final element in document.querySelectorAll('*')) {
      final attributes = element.attributes;
      attributes.remove('style');
      for (final name in [...colorAttributes, 'color']) {
        if (!attributes.containsKey(name)) continue;
        final color = sanitizeColor(attributes[name]);
        if (color == null || (name == 'color' && element.localName != 'font')) {
          attributes.remove(name);
        } else {
          attributes[name] = color;
        }
      }

      switch (element.localName) {
        case 'font':
          attributes.removeWhere(
              (key, _) => !const {...colorAttributes, 'color'}.contains(key));
        case 'ol':
          final start = parseListStart(attributes['start']);
          if (start == null) {
            attributes.remove('start');
          } else {
            attributes['start'] = start.toString();
          }
        case 'a':
          final href = attributes['href'];
          if (href != null && !isAllowedHref(href)) attributes.remove('href');
      }
    }
  }

  /// flutter_html styles for the sanitised colours and list starts of
  /// [document], keyed by attribute selectors. The values are validated, so
  /// they are safe to write into a selector.
  static Map<String, Style> styles(dom.Document document) {
    final result = <String, Style>{};
    for (final element in document.querySelectorAll(
        '[data-mx-color], [data-mx-bg-color], font[color], ol[start]')) {
      final attributes = element.attributes;
      final color = attributes['color'];
      if (color != null && element.localName == 'font') {
        result['font[color="$color"]'] = Style(color: _parse(color));
      }
      final mxColor = attributes['data-mx-color'];
      if (mxColor != null) {
        result['[data-mx-color="$mxColor"]'] = Style(color: _parse(mxColor));
      }
      final background = attributes['data-mx-bg-color'];
      if (background != null) {
        result['[data-mx-bg-color="$background"]'] =
            Style(backgroundColor: _parse(background));
      }
    }
    // Lists last: Style.merge replaces counters, so nothing may follow them.
    for (final element in document.querySelectorAll('ol[start]')) {
      final start = int.parse(element.attributes['start']!);
      result['ol[start="$start"]'] =
          Style(counterReset: {'list-item': start - 1});
    }
    return result;
  }

  static Color _parse(String hex) =>
      Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}
