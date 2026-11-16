import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/utils/clipboard/pasted_file.dart';
import 'package:rooster/ui/organisms/attachment_processor/picked_files.dart';

/// A picked file that fails the test when any of its bytes are asked for:
/// the picker gave its path and size only.
class _Unread extends PlatformFile {
  _Unread(this.reads, {required super.name, required super.size, super.path});

  final List<String> reads;

  @override
  Uint8List? get bytes {
    reads.add(name);
    throw StateError('the bytes of $name were asked for');
  }

  @override
  Stream<List<int>>? get readStream {
    reads.add(name);
    throw StateError('the stream of $name was asked for');
  }
}

/// A picker that hands out [files] and keeps how it was asked.
class _FakePicker extends FilePicker {
  _FakePicker(this.files);

  final List<PlatformFile> files;
  bool? withData;
  bool? withReadStream;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    this.withData = withData;
    this.withReadStream = withReadStream;
    return FilePickerResult(files);
  }
}

void main() {
  const limit = 50 * 1000 * 1000;

  test(
      'native: the picker is asked for paths and sizes; a file over '
      'm.upload.size is refused with no read, one within it is attached by '
      'its path, still unread', () async {
    final reads = <String>[];
    final picker = FilePicker.platform = _FakePicker([
      _Unread(reads, name: 'big.mkv', size: 60 * 1000 * 1000, path: '/v/big'),
      _Unread(reads, name: 'small.zip', size: 2000, path: '/v/small'),
    ]);
    final refused = <(int, int)>[];

    final attached = await pickFileAttachments(
        maxBytes: limit,
        onRefused: (bytes, max) => refused.add((bytes, max)),
        web: false);

    expect(picker.withData, isFalse);
    expect(picker.withReadStream, isFalse);
    expect(reads, isEmpty, reason: 'no byte of any file read');
    expect(refused, [(60 * 1000 * 1000, limit)]);
    expect(attached.single.name, 'small.zip');
    expect(attached.single.path, '/v/small');
    expect(attached.single.data, isNull);
    expect(attached.single.size, 2000);
  });

  test(
      "web: the size comes from the browser's File; a file over the limit is "
      'refused before its stream is opened, one within it is read', () async {
    final reads = <String>[];
    var opened = 0;
    final picker = FilePicker.platform = _FakePicker([
      _Unread(reads, name: 'big.png', size: 60 * 1000 * 1000),
      PlatformFile(
          name: 'small.png',
          size: 3,
          readStream: Stream.multi((out) {
            opened++;
            out
              ..add([1, 2])
              ..add([3])
              ..close();
          })),
    ]);
    final refused = <int>[];

    final attached = await pickFileAttachments(
        maxBytes: limit,
        onRefused: (bytes, _) => refused.add(bytes),
        web: true);

    expect(picker.withData, isFalse);
    expect(picker.withReadStream, isTrue);
    expect(reads, isEmpty);
    expect(refused, [60 * 1000 * 1000]);
    expect(opened, 1);
    expect(attached.single.data, [1, 2, 3]);
  });

  test('no known limit: nothing is refused, the server still checks', () async {
    final reads = <String>[];
    FilePicker.platform = _FakePicker([
      _Unread(reads, name: 'big.mkv', size: 60 * 1000 * 1000, path: '/v/big'),
    ]);
    final attached = await pickFileAttachments(
        maxBytes: null, onRefused: (_, __) => fail('refused'), web: false);
    expect(attached.single.path, '/v/big');
    expect(reads, isEmpty);
  });

  test(
      'native paste: an image over the limit is refused by its length, '
      'before anything decodes it', () async {
    final decoded = <Uint8List>[];
    final refused = <int>[];
    final big = Uint8List(limit + 1);

    final pasted = await pasteNativeImage(
        readImage: () async => big,
        maxBytes: limit,
        onImage: decoded.add,
        onRefused: (bytes, _) => refused.add(bytes));

    expect(pasted, isTrue);
    expect(decoded, isEmpty,
        reason: 'the attachment dialog, which decodes it, never gets it');
    expect(refused, [limit + 1]);

    final small = Uint8List(10);
    await pasteNativeImage(
        readImage: () async => small,
        maxBytes: limit,
        onImage: decoded.add,
        onRefused: (_, __) => fail('refused'));
    expect(decoded, [small]);
  });

  testWidgets('the refusal names both sizes', (tester) async {
    expect(
        messageFileOverUploadLimit(60 * 1024 * 1024, 50 * 1024 * 1024),
        "This file is 60 MB, over this server's limit of 50 MB, so it can't "
        'be sent.');
  });
}
