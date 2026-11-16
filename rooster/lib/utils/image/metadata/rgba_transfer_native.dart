import 'dart:isolate';
import 'dart:typed_data';

/// Straight RGBA on its way to a background isolate, as a
/// [TransferableTypedData]. Packing copies the pixels once, out of the
/// engine's buffer, which can then go; sending moves that copy to the
/// isolate instead of copying it again, and [unpack] there gives it back
/// as it is.
class PackedRgba {
  PackedRgba(Uint8List rgba) : payload = TransferableTypedData.fromList([rgba]);

  final TransferableTypedData payload;

  /// The pixels, on the isolate that encodes them. Once only.
  Uint8List unpack() => payload.materialize().asUint8List();
}
