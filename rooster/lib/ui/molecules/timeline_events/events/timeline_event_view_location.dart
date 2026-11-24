import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_location_uri.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// An `m.location` message as a card: what the sender called the place,
/// its coordinates, and a button that opens it on a map. Nothing is
/// fetched to draw it (no map tile, no picture), so reading the room tells
/// no outside server who is reading; the map opens only when the person
/// asks, after the app's usual question before a link leaves it. A
/// `geo_uri` that is not a valid `geo:` URI is shown as such.
class TimelineEventViewLocation extends StatelessWidget {
  const TimelineEventViewLocation(
      {required this.location,
      this.description,
      this.clientId,
      this.roomId,
      super.key});

  /// Null when the message's `geo_uri` could not be read.
  final MatrixLocationUri? location;
  final String? description;
  final String? clientId;
  final String? roomId;

  static const cardKey = ValueKey('location-card');
  static const openMapKey = ValueKey('location-open-map');
  static const invalidKey = ValueKey('location-invalid');

  static String get labelLocation => Intl.message("Location",
      name: "labelLocation",
      desc: "Title of a place shared in the chat, when the sender gave it "
          "no description");

  static String get promptOpenLocationInMap => Intl.message("Open in map",
      name: "promptOpenLocationInMap",
      desc: "Button on a place shared in the chat that opens it on "
          "OpenStreetMap in the web browser");

  static String get messageLocationInvalid => Intl.message(
      "This location cannot be shown: its coordinates are not "
      "valid",
      name: "messageLocationInvalid",
      desc: "Shown in the chat for a shared place whose coordinates "
          "could not be read");

  static String labelLocationCoordinates(String latitude, String longitude) =>
      Intl.message("$latitude, $longitude",
          name: "labelLocationCoordinates",
          args: [latitude, longitude],
          desc: "The latitude and the longitude of a place shared in the "
              "chat, in decimal degrees, already formatted as numbers in "
              "the app's language");

  static String labelLocationAccuracy(String meters) =>
      Intl.message("Within $meters m",
          name: "labelLocationAccuracy",
          args: [meters],
          desc: "Under a place shared in the chat: how far off it may be, in "
              "metres, already formatted as a number");

  static String labelLocationAltitude(String meters) =>
      Intl.message("Altitude $meters m",
          name: "labelLocationAltitude",
          args: [meters],
          desc: "Under a place shared in the chat: its height above sea "
              "level, in metres, already formatted as a number");

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final location = this.location;
    final description = this.description;

    return Container(
      key: cardKey,
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(location == null ? Icons.location_off : Icons.location_on,
              color: location == null ? colors.error : colors.primary),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelEmphasised(
                  description ?? labelLocation,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (location == null)
                  tiamat.Text.labelLow(messageLocationInvalid, key: invalidKey)
                else ...[
                  SelectableText(coordinates(location)),
                  for (final detail in details(location))
                    tiamat.Text.labelLow(detail),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    key: openMapKey,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(promptOpenLocationInMap),
                    onPressed: () => LinkUtils.open(location.mapLink,
                        context: context,
                        clientId: clientId,
                        contextRoomId: roomId),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String coordinates(MatrixLocationUri location) {
    final format = NumberFormat.decimalPatternDigits(decimalDigits: 6);
    return labelLocationCoordinates(
        format.format(location.latitude), format.format(location.longitude));
  }

  static List<String> details(MatrixLocationUri location) {
    final format = NumberFormat.decimalPattern()..maximumFractionDigits = 1;
    return [
      if (location.uncertainty != null)
        labelLocationAccuracy(format.format(location.uncertainty)),
      if (location.altitude != null)
        labelLocationAltitude(format.format(location.altitude)),
    ];
  }
}
