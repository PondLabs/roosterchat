import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_location_uri.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/common_strings.dart';

/// A place to send, as the person typed it.
typedef LocationToSend = ({MatrixLocationUri location, String? description});

/// The composer's "Send a location": the person types the coordinates (or
/// pastes a `geo:` link) and, if they like, what the place is. The app
/// never reads where the device is: a place is shared only when it is
/// typed here.
class SendLocationForm extends StatefulWidget {
  const SendLocationForm({required this.onSend, super.key});

  final void Function(LocationToSend place) onSend;

  static const coordinatesKey = ValueKey('send-location-coordinates');
  static const descriptionKey = ValueKey('send-location-description');
  static const sendKey = ValueKey('send-location-send');

  /// Asks for a place in [context]; null when the person cancels.
  static Future<LocationToSend?> show(BuildContext context) =>
      AdaptiveDialog.show<LocationToSend>(context,
          title: labelSendLocation,
          builder: (context) => SendLocationForm(
              onSend: (place) => Navigator.of(context).pop(place)));

  static String get labelSendLocation => Intl.message("Send a location",
      name: "labelSendLocation",
      desc: "Title of the dialog, and tooltip of the composer's button, "
          "that sends a place to the chat");

  static String get labelSendLocationCoordinates => Intl.message("Coordinates",
      name: "labelSendLocationCoordinates",
      desc: "Label of the field where the coordinates of a place to send "
          "are typed");

  static String get hintSendLocationCoordinates =>
      Intl.message("Latitude, longitude (e.g. -23.5505, -46.6333)",
          name: "hintSendLocationCoordinates",
          desc: "Hint in the field where the coordinates of a place to send "
              "are typed. Keep the example numbers as they are: they are "
              "typed with a dot");

  static String get labelSendLocationDescription =>
      Intl.message("Description (optional)",
          name: "labelSendLocationDescription",
          desc: "Label of the field where the person may say what the "
              "place they send is");

  static String get errorSendLocationCoordinates => Intl.message(
      "Type a latitude from -90 to 90 and a longitude from -180 to 180, "
      "separated by a comma, or a geo: link",
      name: "errorSendLocationCoordinates",
      desc: "Shown under the coordinates of a place to send when they cannot "
          "be read. Keep \"geo:\" as it is");

  static String get promptSendLocation => Intl.message("Send",
      name: "promptSendLocation",
      desc: "Button that sends the place typed in the dialog to the chat");

  @override
  State<SendLocationForm> createState() => _SendLocationFormState();
}

class _SendLocationFormState extends State<SendLocationForm> {
  final coordinates = TextEditingController();
  final description = TextEditingController();
  MatrixLocationUri? location;
  bool showError = false;

  @override
  void dispose() {
    coordinates.dispose();
    description.dispose();
    super.dispose();
  }

  void submit() {
    final location = this.location;
    if (location == null) {
      setState(() => showError = true);
      return;
    }
    final text = description.text.trim();
    widget
        .onSend((location: location, description: text.isEmpty ? null : text));
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: SendLocationForm.coordinatesKey,
            controller: coordinates,
            autofocus: true,
            decoration: InputDecoration(
              labelText: SendLocationForm.labelSendLocationCoordinates,
              hintText: SendLocationForm.hintSendLocationCoordinates,
              errorText: showError && location == null
                  ? SendLocationForm.errorSendLocationCoordinates
                  : null,
              errorMaxLines: 3,
            ),
            onChanged: (value) =>
                setState(() => location = MatrixLocationUri.fromInput(value)),
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            key: SendLocationForm.descriptionKey,
            controller: description,
            maxLength: 200,
            decoration: InputDecoration(
                labelText: SendLocationForm.labelSendLocationDescription),
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(CommonStrings.promptCancel),
              ),
              FilledButton.icon(
                key: SendLocationForm.sendKey,
                icon: const Icon(Icons.location_on, size: 18),
                label: Text(SendLocationForm.promptSendLocation),
                onPressed: location == null ? null : submit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
