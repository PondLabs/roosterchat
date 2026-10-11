// Public name colors (MSC4522 `eu.she-a.color`): what is read from a profile,
// what is written to ours, and how often other people's are asked for. Names
// are drawn synchronously from whatever is known, so the cache must never
// fetch twice for one person, never flood the homeserver, and say when a
// color actually changes so the names drawn with the old one repaint.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:rooster/client/components/user_color/name_color_cache.dart';
import 'package:rooster/client/components/user_color/user_color_component.dart';
import 'package:rooster/client/matrix/components/user_color/matrix_user_color_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:tiamat/config/style/theme_changer.dart';

const me = '@me:example.org';
const friend = '@friend:example.org';

const red = NameColor(onDark: Color(0xffff8080), onLight: Color(0xffa00000));
const blue = NameColor(onDark: Color(0xff8080ff), onLight: Color(0xff0000a0));

/// Answers each fetch when the test says so.
class FakeFetch {
  final calls = <String>[];
  final _pending = <String, Completer<Object?>>{};

  Future<Object?> call(String userId) {
    calls.add(userId);
    return (_pending[userId] = Completer()).future;
  }

  void answer(String userId, Object? value) =>
      _pending.remove(userId)!.complete(value);

  /// No answer, the way a timeout or a dropped connection ends.
  void fail(String userId) =>
      _pending.remove(userId)!.completeError(TimeoutException('no answer'));
}

matrix.MatrixException notFound() => matrix.MatrixException.fromJson(
    {'errcode': 'M_NOT_FOUND', 'error': 'Profile field not found'});

class FakeSdkClient implements matrix.Client {
  final profiles = <String, Map<String, Object?>>{};
  var profileReads = 0;
  Map<String, Object?>? writtenAccountData;

  @override
  final Map<String, matrix.BasicEvent> accountData = {};

  @override
  final CachedStreamController<matrix.SyncUpdate> onSync =
      CachedStreamController();

  @override
  String? get userID => me;

  @override
  Future<Map<String, Object?>> getProfileField(
      String userId, String keyName) async {
    profileReads++;
    final value = profiles[userId]?[keyName];
    if (value == null) throw notFound();
    return {keyName: value};
  }

  @override
  Future<Map<String, Object?>> setProfileField(
      String userId, String keyName, Map<String, Object?> body) async {
    (profiles[userId] ??= {})[keyName] = body[keyName];
    return {};
  }

  @override
  Future<Map<String, Object?>> deleteProfileField(
      String userId, String keyName) async {
    if (profiles[userId]?.remove(keyName) == null) throw notFound();
    return {};
  }

  @override
  Future<void> setAccountData(
      String userId, String type, Map<String, Object?> content) async {
    writtenAccountData = content;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMatrixClient implements MatrixClient {
  final sdk = FakeSdkClient();

  @override
  matrix.Client get matrixClient => sdk;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('parse', () {
    test('reads #RRGGBB in either case, and #RGB', () {
      expect(
          NameColorCache.parse({'on_dark': '#AbCdEf', 'on_light': '#f0a'}),
          const NameColor(
              onDark: Color(0xffabcdef), onLight: Color(0xffff00aa)));
    });

    test('tolerates a missing #', () {
      expect(
          NameColorCache.parse({'on_dark': 'abcdef', 'on_light': '0F0'}),
          const NameColor(
              onDark: Color(0xffabcdef), onLight: Color(0xff00ff00)));
    });

    test('is always opaque', () {
      expect(
          NameColorCache.parse({'on_dark': '#000', 'on_light': '#000000'}),
          const NameColor(
              onDark: Color(0xff000000), onLight: Color(0xff000000)));
    });

    test('one valid variant is used for both', () {
      const only = Color(0xff123456);
      const both = NameColor(onDark: only, onLight: only);
      expect(NameColorCache.parse({'on_light': '#123456'}), both);
      expect(NameColorCache.parse({'on_dark': '#123456', 'on_light': 'red'}),
          both);
    });

    test('anything else is no color', () {
      for (final garbage in [
        '#ggg',
        '#12345',
        '#1234567',
        '#80123456',
        'red',
        '',
        ' #123456',
        12,
        null,
        ['#123456'],
      ]) {
        expect(NameColorCache.parse({'on_dark': garbage, 'on_light': garbage}),
            isNull,
            reason: '$garbage');
      }
      expect(NameColorCache.parse('#123456'), isNull);
      expect(NameColorCache.parse(null), isNull);
      expect(NameColorCache.parse(['#123456']), isNull);
      expect(NameColorCache.parse({}), isNull);
    });

    test('writes lowercase #rrggbb that reads back the same', () {
      const color =
          NameColor(onDark: Color(0xffABCDEF), onLight: Color(0xff012345));
      final json = NameColorCache.serialize(color);
      expect(json, {'on_dark': '#abcdef', 'on_light': '#012345'});
      expect(NameColorCache.parse(json), color);
    });
  });

  group('cache', () {
    late FakeFetch fetch;
    late DateTime now;
    late NameColorCache cache;
    late List<String> emitted;

    setUp(() {
      fetch = FakeFetch();
      now = DateTime(2026, 10, 11, 12);
      cache = NameColorCache(fetch.call, now: () => now);
      emitted = [];
      cache.onChanged.listen(emitted.add);
    });

    test('asks once for someone however often their name is drawn', () async {
      cache.request(friend);
      cache.request(friend);
      expect(fetch.calls, [friend]);

      fetch.answer(friend, NameColorCache.serialize(red));
      await pumpEventQueue();
      cache.request(friend);
      expect(fetch.calls, [friend]);
      expect(cache.get(friend), red);
    });

    test('ignores ids that are not Matrix user ids', () {
      cache.request('!room:example.org');
      cache.request('');
      expect(fetch.calls, isEmpty);
    });

    test('at most four at once, the newest request first', () async {
      for (var i = 1; i <= 7; i++) {
        cache.request('@$i:example.org');
      }
      expect(fetch.calls,
          ['@1', '@2', '@3', '@4'].map((i) => '$i:example.org').toList());

      // Scrolled back to 5: it is the newest request now.
      cache.request('@5:example.org');
      fetch.answer('@1:example.org', null);
      await pumpEventQueue();
      expect(fetch.calls.last, '@5:example.org');

      fetch.fail('@2:example.org');
      await pumpEventQueue();
      expect(fetch.calls.last, '@7:example.org');

      fetch.answer('@3:example.org', null);
      await pumpEventQueue();
      expect(fetch.calls.last, '@6:example.org');
      expect(fetch.calls, hasLength(7));
    });

    test('asks again after 30 minutes, drawing the old color meanwhile',
        () async {
      cache.request(friend);
      fetch.answer(friend, NameColorCache.serialize(red));
      await pumpEventQueue();

      now = now.add(const Duration(minutes: 29));
      cache.request(friend);
      expect(fetch.calls, hasLength(1));

      now = now.add(const Duration(minutes: 2));
      cache.request(friend);
      expect(fetch.calls, hasLength(2));
      expect(cache.get(friend), red);

      fetch.answer(friend, NameColorCache.serialize(blue));
      await pumpEventQueue();
      expect(cache.get(friend), blue);
    });

    test('keeps the old color on an error and asks again after a minute',
        () async {
      cache.request(friend);
      fetch.answer(friend, NameColorCache.serialize(red));
      await pumpEventQueue();
      expect(emitted, [friend]);

      now = now.add(const Duration(minutes: 31));
      cache.request(friend);
      fetch.fail(friend);
      await pumpEventQueue();
      expect(cache.get(friend), red);
      expect(emitted, [friend]);

      now = now.add(const Duration(seconds: 30));
      cache.request(friend);
      expect(fetch.calls, hasLength(2));

      now = now.add(const Duration(seconds: 31));
      cache.request(friend);
      expect(fetch.calls, hasLength(3));
    });

    test('says so only when the color changed', () async {
      Future<void> refetch(Object? value) async {
        now = now.add(NameColorCache.maxAge);
        cache.request(friend);
        fetch.answer(friend, value);
        await pumpEventQueue();
      }

      await refetch(null);
      expect(emitted, isEmpty);

      await refetch(NameColorCache.serialize(red));
      expect(emitted, [friend]);

      await refetch({'on_dark': '#FF8080', 'on_light': '#a00000'});
      expect(emitted, [friend]);

      await refetch(NameColorCache.serialize(blue));
      expect(emitted, [friend, friend]);

      await refetch('garbage');
      expect(emitted, [friend, friend, friend]);
      expect(cache.get(friend), isNull);
    });

    test('a color set while a fetch is on its way wins', () async {
      cache.request(me);
      now = now.add(const Duration(seconds: 1));
      cache.set(me, blue);
      fetch.answer(me, NameColorCache.serialize(red));
      await pumpEventQueue();
      expect(cache.get(me), blue);
    });
  });

  group('MatrixUserColorComponent', () {
    late FakeMatrixClient client;
    late MatrixUserColorComponent component;
    late List<String> emitted;

    setUp(() {
      client = FakeMatrixClient();
      component = MatrixUserColorComponent(client);
      emitted = [];
      component.onColorChanged.listen(emitted.add);
    });

    tearDown(() => ThemeChanger.brightness = Brightness.dark);

    test('our override, then their public color, then nothing', () {
      client.sdk.accountData[MatrixUserColorComponent.key] = matrix.BasicEvent(
          type: MatrixUserColorComponent.key, content: {friend: '#00ff00'});
      component.publicColors.set(friend, red);
      component.publicColors.set(me, red);

      expect(component.getColor(friend), const Color(0xff00ff00));
      expect(component.getOverride(friend), const Color(0xff00ff00));

      expect(component.getColor(me), red.onDark);
      ThemeChanger.brightness = Brightness.light;
      expect(component.getColor(me), red.onLight);
      expect(component.getOverride(me), isNull);

      expect(component.getColor('@nobody:example.org'), isNull);
    });

    test('reads the field out of the profile response', () async {
      client.sdk.profiles[friend] = {
        NameColorCache.key: NameColorCache.serialize(red)
      };
      component.requestPublicColor(friend);
      await pumpEventQueue();
      expect(component.getColor(friend), red.onDark);
      expect(emitted, [friend]);
    });

    test('a field that is not set is no color, until it is stale', () async {
      component.requestPublicColor(friend);
      await pumpEventQueue();
      expect(component.getColor(friend), isNull);
      expect(emitted, isEmpty);

      component.requestPublicColor(friend);
      await pumpEventQueue();
      expect(client.sdk.profileReads, 1);
    });

    test('switching between light and dark repaints the public colors',
        () async {
      client.sdk.accountData[MatrixUserColorComponent.key] = matrix.BasicEvent(
          type: MatrixUserColorComponent.key, content: {me: '#00ff00'});
      component.publicColors.set(friend, red);
      await pumpEventQueue();
      emitted.clear();

      ThemeChanger.brightness = Brightness.light;
      ThemeChanger.onThemeChanged.add(ThemeData(brightness: Brightness.light));
      await pumpEventQueue();
      expect(emitted, [friend]);
      expect(component.getColor(friend), red.onLight);

      // And back to dark, whatever the app started in.
      ThemeChanger.brightness = Brightness.dark;
      ThemeChanger.onThemeChanged.add(ThemeData(brightness: Brightness.dark));
      await pumpEventQueue();
      expect(emitted, [friend, friend]);
      expect(component.getColor(friend), red.onDark);
    });

    test('setting ours writes MSC4522, updates the cache and says so',
        () async {
      await component.setOwnPublicColor(red);
      expect(client.sdk.profiles[me], {
        NameColorCache.key: {'on_dark': '#ff8080', 'on_light': '#a00000'}
      });
      expect(component.getColor(me), red.onDark);
      await pumpEventQueue();
      expect(emitted, [me]);

      expect(await component.getOwnPublicColor(), red);

      await component.setOwnPublicColor(null);
      expect(client.sdk.profiles[me], isEmpty);
      expect(component.getColor(me), isNull);
      await pumpEventQueue();
      expect(emitted, [me, me]);

      expect(await component.getOwnPublicColor(), isNull);
      await component.setOwnPublicColor(null);
    });

    test('an override draws at once, and one from another session repaints',
        () async {
      await component.setColor(friend, const Color(0xff00ff00));
      expect(client.sdk.writtenAccountData, {friend: '#00ff00'});
      expect(component.getColor(friend), const Color(0xff00ff00));
      await pumpEventQueue();
      expect(emitted, [friend]);

      // Our own write coming back through sync changes nothing.
      final echo = matrix.BasicEvent(
          type: MatrixUserColorComponent.key, content: {friend: '#00ff00'});
      client.sdk.onSync
          .add(matrix.SyncUpdate(nextBatch: '1', accountData: [echo]));
      await pumpEventQueue();
      expect(emitted, [friend]);

      // Another session cleared it and recolored someone else.
      final other = matrix.BasicEvent(
          type: MatrixUserColorComponent.key, content: {me: '#0000ff'});
      client.sdk.accountData[MatrixUserColorComponent.key] = other;
      client.sdk.onSync
          .add(matrix.SyncUpdate(nextBatch: '2', accountData: [other]));
      await pumpEventQueue();
      expect(emitted, [friend, friend, me]);
      expect(component.getOverride(friend), isNull);
    });
  });
}
