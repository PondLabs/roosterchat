/// A place from an `m.location` message: its `geo_uri` (RFC 5870), read
/// strictly. The URI comes from whoever sent the message, so anything but a
/// well-formed `geo:` URI on WGS 84 is refused, and nothing in it is used
/// as it was written: the map link is built from the numbers alone.
library;

/// A parsed `geo:` URI.
class MatrixLocationUri {
  const MatrixLocationUri._({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.uncertainty,
  });

  /// Degrees north, from -90 to 90.
  final double latitude;

  /// Degrees east, from -180 to 180.
  final double longitude;

  /// Metres above the WGS 84 ellipsoid, when given.
  final double? altitude;

  /// How far off the place may be, in metres (`u=`), when given.
  final double? uncertainty;

  /// Longer than any sensible `geo:` URI: refused before it is read.
  static const maxLength = 256;

  static final _number = RegExp(r'^-?\d{1,3}(\.\d{1,15})?$');
  static final _altitude = RegExp(r'^-?\d{1,9}(\.\d{1,15})?$');
  static final _uncertainty = RegExp(r'^\d{1,9}(\.\d{1,15})?$');

  /// A parameter's name and value (RFC 5870 `pname` and `pvalue`, with
  /// percent-escapes): letters, digits and the unreserved marks only.
  static final _parameter =
      RegExp(r'^[A-Za-z0-9-]+(=[A-Za-z0-9\-._~!$&' "'" r'()*+:@%\[\]]*)?$');

  /// [uri] read as a `geo:` URI, or null when it is not one: another
  /// scheme, coordinates out of range, another coordinate system, a
  /// malformed parameter or characters a `geo:` URI cannot hold.
  static MatrixLocationUri? tryParse(Object? uri) {
    if (uri is! String) return null;
    final text = uri.trim();
    if (text.isEmpty || text.length > maxLength) return null;
    if (text.length < 4 || text.substring(0, 4).toLowerCase() != 'geo:') {
      return null;
    }

    final parts = text.substring(4).split(';');
    final coordinates = parts.first.split(',');
    if (coordinates.length < 2 || coordinates.length > 3) return null;
    if (!coordinates.take(2).every(_number.hasMatch)) return null;
    if (coordinates.length == 3 && !_altitude.hasMatch(coordinates[2])) {
      return null;
    }

    final latitude = double.parse(coordinates[0]);
    final longitude = double.parse(coordinates[1]);
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    final altitude =
        coordinates.length == 3 ? double.parse(coordinates[2]) : null;

    double? uncertainty;
    final seen = <String>{};
    for (final parameter in parts.skip(1)) {
      if (!_parameter.hasMatch(parameter)) return null;
      final split = parameter.indexOf('=');
      final name = (split == -1 ? parameter : parameter.substring(0, split))
          .toLowerCase();
      final value = split == -1 ? null : parameter.substring(split + 1);
      if (!seen.add(name)) return null;
      switch (name) {
        // RFC 5870 3.3: crs comes first, and only wgs84 is understood.
        case 'crs':
          if (seen.length != 1 || value?.toLowerCase() != 'wgs84') return null;
        case 'u':
          if (value == null || !_uncertainty.hasMatch(value)) return null;
          uncertainty = double.parse(value);
      }
    }

    return MatrixLocationUri._(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      uncertainty: uncertainty,
    );
  }

  /// [latitude] and [longitude] typed by a person: a `geo:` URI, or the
  /// two numbers separated by a comma (and spaces).
  static MatrixLocationUri? fromInput(String input) {
    final text = input.trim();
    if (text.toLowerCase().startsWith('geo:')) return tryParse(text);
    final numbers = text.split(RegExp(r'\s*,\s*|\s+'));
    if (numbers.length != 2) return null;
    return tryParse('geo:${numbers[0]},${numbers[1]}');
  }

  /// The URI to send, written again from the numbers.
  String get geoUri {
    final buffer = StringBuffer('geo:${_format(latitude)},'
        '${_format(longitude)}');
    if (altitude != null) buffer.write(',${_format(altitude!)}');
    if (uncertainty != null) buffer.write(';u=${_format(uncertainty!)}');
    return buffer.toString();
  }

  /// The place on OpenStreetMap, built from the numbers only. Opened only
  /// when the person asks: nothing is fetched to show the message.
  Uri get mapLink => Uri.https('www.openstreetmap.org', '/', {
        'mlat': _format(latitude),
        'mlon': _format(longitude),
      }).replace(fragment: 'map=16/${_format(latitude)}/${_format(longitude)}');

  static String _format(double value) {
    final text = value.toStringAsFixed(6);
    final trimmed = text.replaceFirst(RegExp(r'\.?0+$'), '');
    return trimmed == '-0' ? '0' : trimmed;
  }

  @override
  String toString() => geoUri;
}
