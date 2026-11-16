import 'dart:typed_data';

import 'package:rooster/cache/own_media_cache.dart';
import 'package:test/test.dart';

const mb = 1024 * 1024;

Uint8List bytesOf(int length, int fill) =>
    Uint8List(length)..fillRange(0, length, fill);

/// The web's own media: one in-memory map for the session, 64 MB for every
/// account together, the oldest entry out first.
void main() {
  test('the app\'s map holds 64 MB', () {
    expect(OwnMediaMemory.instance.limitBytes, 64 * mb);
    // With no file cache (the web), an account's own media is that map.
    final cache = OwnMediaCache.forAccount('a');
    expect(cache, isA<MemoryOwnMediaCache>());
    expect((cache as MemoryOwnMediaCache).memory, OwnMediaMemory.instance);
  });

  test('over 64 MB, the oldest entries go first until it fits', () async {
    final memory = OwnMediaMemory();
    final a = MemoryOwnMediaCache('a', memory);
    final b = MemoryOwnMediaCache('b', memory);
    await a.write('mxc://hs/1', bytesOf(20 * mb, 1));
    await b.write('mxc://hs/2', bytesOf(20 * mb, 2));
    await a.write('mxc://hs/3', bytesOf(20 * mb, 3));
    expect(memory.bytes, 60 * mb);

    // 60 + 10 > 64: the oldest (1) goes, whichever account it was.
    await b.write('mxc://hs/4', bytesOf(10 * mb, 4));
    expect(await a.read('mxc://hs/1'), isNull);
    expect((await b.read('mxc://hs/2'))![0], 2);
    expect((await a.read('mxc://hs/3'))![0], 3);
    expect(memory.bytes, 50 * mb);

    // 50 + 40 > 64: 2 goes, 30 + 40 still is: 3 goes too; 4 stays.
    await a.write('mxc://hs/5', bytesOf(40 * mb, 5));
    expect(await b.read('mxc://hs/2'), isNull);
    expect(await a.read('mxc://hs/3'), isNull);
    expect((await b.read('mxc://hs/4'))![0], 4);
    expect((await a.read('mxc://hs/5'))![0], 5);
    expect(memory.bytes, 50 * mb);
    expect(memory.bytes, lessThanOrEqualTo(memory.limitBytes));
  });

  test('a file of exactly 64 MB fits alone; a larger one is not kept',
      () async {
    final memory = OwnMediaMemory();
    final a = MemoryOwnMediaCache('a', memory);
    await a.write('small', bytesOf(mb, 1));
    await a.write('whole', bytesOf(64 * mb, 2));
    expect(await a.read('small'), isNull);
    expect(memory.bytes, 64 * mb);

    await a.write('huge', bytesOf(64 * mb + 1, 3));
    expect(await a.read('huge'), isNull);
    expect(await a.read('whole'), isNotNull, reason: 'nothing made way');
  });

  test('writing a key again replaces it and counts once', () async {
    final memory = OwnMediaMemory(limitBytes: 10);
    final a = MemoryOwnMediaCache('a', memory);
    await a.write('k', bytesOf(6, 1));
    await a.write('k', bytesOf(6, 2));
    expect(memory.bytes, 6);
    expect((await a.read('k'))![0], 2);
  });

  test('accounts are apart: one\'s keys, and clearing one, leave the other',
      () async {
    final memory = OwnMediaMemory();
    final a = MemoryOwnMediaCache('a', memory);
    final b = MemoryOwnMediaCache('b', memory);
    await a.write('mxc://hs/x', bytesOf(4, 1));
    await b.write('mxc://hs/x', bytesOf(4, 2));
    expect((await a.read('mxc://hs/x'))![0], 1);
    expect((await b.read('mxc://hs/x'))![0], 2);

    await a.clear();
    expect(await a.read('mxc://hs/x'), isNull);
    expect((await b.read('mxc://hs/x'))![0], 2);
    expect(memory.bytes, 4);
  });
}
