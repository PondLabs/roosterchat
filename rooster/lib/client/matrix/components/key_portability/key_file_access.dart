import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Saving and opening a key export file, so a test can stand in for the
/// system's dialogs.
abstract class KeyFileAccess {
  /// Saves [bytes] as [fileName] where the person picks; false when they
  /// cancelled.
  Future<bool> save(String fileName, Uint8List bytes);

  /// The bytes of the file the person picks, or null when they cancelled.
  Future<Uint8List?> pick();
}

/// [KeyFileAccess] through `file_picker`, with bytes only (no `dart:io`):
/// on desktop and Android the save dialog writes them, in a browser they
/// are downloaded, and a picked file is read whole on every platform.
class FilePickerKeyFileAccess implements KeyFileAccess {
  const FilePickerKeyFileAccess();

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    final path = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      bytes: bytes,
    );
    // A browser downloads the file, with no path to give back.
    return kIsWeb || path != null;
  }

  @override
  Future<Uint8List?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    return result?.files.firstOrNull?.bytes;
  }
}
