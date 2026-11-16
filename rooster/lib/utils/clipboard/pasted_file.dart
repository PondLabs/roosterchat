import 'dart:typed_data';

/// A file pasted into the page, a screenshot most of the time.
class PastedFile {
  const PastedFile(this.data, {this.name, this.mimeType});

  final Uint8List data;
  final String? name;
  final String? mimeType;
}

/// Whether a pasted file of [bytes] may be sent under [maxBytes] (null: the
/// limit is not known, and the server checks). Asked before the file is
/// read, decoded or copied.
bool pastedFileFits(int bytes, int? maxBytes) =>
    maxBytes == null || bytes <= maxBytes;

/// The image pasted on native, given to [onImage] when it fits [maxBytes]
/// (the server's limit on uploads), before anything decodes it; its size
/// goes to [onRefused] when it does not. [readImage] reads the clipboard
/// (`Pasteboard.image`). Returns whether an image was pasted at all.
Future<bool> pasteNativeImage({
  required Future<Uint8List?> Function() readImage,
  required int? maxBytes,
  required void Function(Uint8List image) onImage,
  required void Function(int bytes, int maxBytes) onRefused,
}) async {
  final image = await readImage();
  if (image == null) return false;
  if (!pastedFileFits(image.length, maxBytes)) {
    onRefused(image.length, maxBytes!);
  } else {
    onImage(image);
  }
  return true;
}
