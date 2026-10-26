import 'dart:typed_data';

/// A file pasted into the page, a screenshot most of the time.
class PastedFile {
  const PastedFile(this.data, {this.name, this.mimeType});

  final Uint8List data;
  final String? name;
  final String? mimeType;
}
