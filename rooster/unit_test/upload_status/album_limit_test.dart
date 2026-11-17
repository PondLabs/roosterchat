@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/photo_album_room/photo.dart';
import 'package:rooster/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:rooster/client/components/photo_album_room/photo_album_timeline.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/organisms/attachment_processor/picked_files.dart';
import 'package:rooster/ui/organisms/photo_albums/photo_album_view.dart';
import 'package:rooster/ui/organisms/photo_albums/photos_upload_view.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import '../media_prepare/fakes.dart';
import '../pending_media/chat_harness.dart';

/// A dropped photo of [size] bytes that fails the test when any of its
/// bytes is read: only its length may be asked.
class _Unread extends XFile {
  _Unread(super.path, this.size);

  final int size;
  final List<String> reads = [];

  @override
  Future<int> length() async => size;

  @override
  Future<Uint8List> readAsBytes() {
    reads.add('readAsBytes');
    throw StateError('the bytes of $name were read');
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    reads.add('openRead');
    throw StateError('the bytes of $name were read');
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) {
    reads.add('readAsString');
    throw StateError('the bytes of $name were read');
  }
}

class _Timeline implements PhotoAlbumTimeline {
  @override
  Stream<Photo> get onAdded => const Stream.empty();
  @override
  Stream<Photo> get onChanged => const Stream.empty();
  @override
  Stream<Photo> get onRemoved => const Stream.empty();
  @override
  List<Photo> get photos => const [];
  @override
  bool get canLoadMorePhotos => false;
  @override
  Future<void> loadMorePhotos() async {}
  @override
  Future<void> dispose() async {}
}

/// An album whose uploads are noted, never sent.
class _Album implements PhotoAlbumRoom<Client, Room> {
  _Album(this.room);

  @override
  final Room room;
  @override
  Client get client => room.client;
  @override
  bool get canUpload => true;
  final List<List<PickedPhoto>> uploads = [];

  @override
  Future<PhotoAlbumTimeline> getTimeline() async => _Timeline();

  @override
  Future<void> uploadPhotos(List<PickedPhoto> photos,
          {bool sendOriginal = false, bool extractMetadata = true}) async =>
      uploads.add(photos);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const limit = 50 * 1000 * 1000;
  const over = 60 * 1000 * 1000;

  test(
      "photos for an album: one over the server's limit is refused by its "
      'length, unread; the others go on, still unread', () async {
    final asked = <String>[];
    PickedPhoto photo(String name, int size) => PickedPhoto(
        name: name,
        length: () async => size,
        getBytes: () {
          asked.add(name);
          throw StateError('the bytes of $name were read');
        });
    final refused = <(int, int)>[];

    final admitted = await admitPickedPhotos(
        [photo('big.jpg', over), photo('small.jpg', 1000)],
        maxBytes: limit, onRefused: (bytes, max) => refused.add((bytes, max)));

    expect(asked, isEmpty);
    expect(refused, [(over, limit)]);
    expect([for (final p in admitted) p.name], ['small.jpg']);
  });

  for (final locale in ['en', 'pt']) {
    testWidgets(
        "a photo over the server's limit dropped on an album is refused "
        'unread, with the sentence the chat gives, and no upload dialog '
        'opens ($locale)', (tester) async {
      await tester.runAsync(() => initializeMessages(locale));
      intl.Intl.defaultLocale = locale;
      final appLimit = uploadLimitOf;
      addTearDown(() {
        intl.Intl.defaultLocale = null;
        uploadLimitOf = appLimit;
      });
      uploadLimitOf = (_) async => limit;
      final album = _Album(FakeRoom(FakeClient('a'), '!album',
          preparer: fakePreparer(FakeEngine(width: 400, height: 300))));
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
          home: Scaffold(body: PhotoAlbumView(album))));
      await tester.pump();
      await tester.pump();
      final big = _Unread('/photos/big.jpg', over);

      EventBus.onFileDropped.add(DropDoneDetails(
          files: [big],
          localPosition: const Offset(400, 300),
          globalPosition: const Offset(400, 300)));
      await tester.pump();
      await tester.pump();

      final sentence = messageFileOverUploadLimit(over, limit);
      expect(sentence,
          contains(locale == 'pt' ? 'deste servidor' : "server's limit"));
      expect(find.text(sentence), findsOneWidget);
      expect(big.reads, isEmpty, reason: 'not one byte read');
      expect(find.byType(PhotosAlbumUploadView), findsNothing);
      expect(album.uploads, isEmpty);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
