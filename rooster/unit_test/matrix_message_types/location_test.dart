// Criterion 2: `m.location` reads `geo:lat,lon;u=acc` (RFC 5870) with
// positive and negative coordinates and an altitude, refuses a malformed or
// unsafe `geo_uri` without a crash, draws a card that fetches nothing, and
// sends a valid `m.location`, from the room and from the composer's form.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_location_uri.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_location.dart';
import 'package:rooster/ui/organisms/chat/send_location_dialog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../pending_media/matrix_fakes.dart';
import 'harness.dart';

void main() {
  group('geo URI parsing', () {
    test('reads latitude, longitude and uncertainty', () {
      final place = MatrixLocationUri.tryParse('geo:51.5008,0.1247;u=35')!;
      expect(place.latitude, 51.5008);
      expect(place.longitude, 0.1247);
      expect(place.uncertainty, 35);
      expect(place.altitude, isNull);
    });

    test('reads negative coordinates', () {
      final place = MatrixLocationUri.tryParse('geo:-23.5505,-46.6333')!;
      expect(place.latitude, -23.5505);
      expect(place.longitude, -46.6333);
      expect(place.uncertainty, isNull);
    });

    test('reads an altitude, a crs of wgs84 and other parameters', () {
      final place =
          MatrixLocationUri.tryParse('GEO:-33.8688,151.2093,58.5;crs=wgs84;'
              'u=12.5;foo=bar')!;
      expect(place.latitude, -33.8688);
      expect(place.longitude, 151.2093);
      expect(place.altitude, 58.5);
      expect(place.uncertainty, 12.5);
    });

    test('takes the edges of the ranges', () {
      expect(MatrixLocationUri.tryParse('geo:90,180'), isNotNull);
      expect(MatrixLocationUri.tryParse('geo:-90,-180'), isNotNull);
      expect(MatrixLocationUri.tryParse('geo:0,0'), isNotNull);
    });

    for (final bad in <Object?>[
      null,
      42,
      '',
      'geo:',
      'geo:51.5',
      'geo:51.5;u=10',
      'geo:91,0',
      'geo:0,181',
      'geo:-90.1,0',
      'geo:1,2,3,4',
      'geo:abc,def',
      'geo:1e2,3',
      'geo:NaN,0',
      'geo:Infinity,0',
      'geo:1,2;u=-5',
      'geo:1,2;u=',
      'geo:1,2;u=abc',
      'geo:1,2;u=1;u=2',
      'geo:1,2;crs=epsg:4326',
      'geo:1,2;u=3;crs=wgs84',
      'geo:1,2;<script>alert(1)</script>',
      'geo:1,2;x="y"',
      'geo:1,2?q=pizza',
      'geo:1,2#here',
      'geo: 1, 2',
      'geo:1,2\nhttps://evil.example',
      'javascript:alert(1)//geo:1,2',
      'https://maps.example/?q=1,2',
      'http://evil.example/geo:1,2',
      'mxc://server/media',
      'geo:1,2;${'a' * 300}',
    ]) {
      test(
          'refuses ${bad is String && bad.length > 40 ? '${bad.substring(0, 40)}…' : bad}',
          () {
        expect(MatrixLocationUri.tryParse(bad), isNull);
      });
    }

    test('writes the URI again from its numbers', () {
      expect(
          MatrixLocationUri.tryParse('geo:51.500800,-0.1247000;u=35')!.geoUri,
          'geo:51.5008,-0.1247;u=35');
      expect(
          MatrixLocationUri.tryParse('geo:-0,10,100')!.geoUri, 'geo:0,10,100');
    });

    test('the map link is built from the numbers only', () {
      final link =
          MatrixLocationUri.tryParse('geo:-23.5505,-46.6333;u=20;foo=bar')!
              .mapLink;
      expect(link.scheme, 'https');
      expect(link.host, 'www.openstreetmap.org');
      expect(link.queryParameters, {'mlat': '-23.5505', 'mlon': '-46.6333'});
      expect(link.fragment, 'map=16/-23.5505/-46.6333');
      expect(link.toString(), isNot(contains('foo')));
    });

    test('a person may type the coordinates or a geo: link', () {
      expect(MatrixLocationUri.fromInput(' -23.5505, -46.6333 ')!.geoUri,
          'geo:-23.5505,-46.6333');
      expect(MatrixLocationUri.fromInput('-23.5505 -46.6333')!.geoUri,
          'geo:-23.5505,-46.6333');
      expect(MatrixLocationUri.fromInput('geo:10,20;u=5')!.geoUri,
          'geo:10,20;u=5');
      expect(MatrixLocationUri.fromInput('São Paulo'), isNull);
      expect(MatrixLocationUri.fromInput('100, 20'), isNull);
      expect(MatrixLocationUri.fromInput('1, 2, 3'), isNull);
    });
  });

  group('m.location messages', () {
    late MatrixClient client;
    late MatrixRoom room;
    late MediaTransport transport;

    setUpAll(() async {
      sqfliteFfiInit();
      (client, room, transport) = await messageTypesRoom('location_test');
    });

    tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

    test('the place comes from geo_uri, else from MSC3488', () {
      final event = convertMessage(room, {
        'msgtype': 'm.location',
        'body': 'Big Ben, London',
        'geo_uri': 'geo:51.5008,0.1247;u=35',
      });
      expect(event.isLocation, isTrue);
      expect(event.location!.geoUri, 'geo:51.5008,0.1247;u=35');
      expect(event.locationDescription, 'Big Ben, London');

      final extensible = convertMessage(room, {
        'msgtype': 'm.location',
        'body': 'Location geo:10,20 at 2026-01-01',
        'org.matrix.msc3488.location': {
          'uri': 'geo:10,20',
          'description': 'The coop',
        },
      });
      expect(extensible.location!.geoUri, 'geo:10,20');
      expect(extensible.locationDescription, 'The coop');
    });

    test('a body that is only the URI is no description', () {
      final event = convertMessage(room, {
        'msgtype': 'm.location',
        'body': 'Location geo:10,20 at 2026-01-01',
        'geo_uri': 'geo:10,20',
      });
      expect(event.locationDescription, isNull);
    });

    test('a malformed geo_uri gives no place and no exception', () {
      for (final geo in <Object?>[
        'javascript:alert(1)',
        'geo:999,999',
        {'not': 'a string'},
        12,
        null,
      ]) {
        final event = convertMessage(room, {
          'msgtype': 'm.location',
          'body': 'somewhere',
          'geo_uri': geo,
        });
        expect(event.location, isNull, reason: '$geo');
      }
    });

    test('other messages have no place', () {
      final event =
          convertMessage(room, {'msgtype': 'm.text', 'body': 'geo:1,2'});
      expect(event.isLocation, isFalse);
      expect(event.location, isNull);
    });

    for (final locale in ['en', 'pt']) {
      testWidgets('the card shows the place and fetches nothing ($locale)',
          (tester) async {
        await useLocale(locale);
        final overrides = CountingHttpOverrides();
        await HttpOverrides.runZoned(() async {
          await pumpMessage(tester, room, {
            'msgtype': 'm.location',
            'body': 'Big Ben, London',
            'geo_uri': 'geo:-51.5008,-0.1247,30;u=35',
            // A map picture the sender attached: never loaded.
            'info': {'thumbnail_url': 'mxc://evil.example/tile'},
          });
        }, createHttpClient: overrides.createHttpClient);

        expect(find.byKey(TimelineEventViewLocation.cardKey), findsOneWidget);
        expect(find.text('Big Ben, London'), findsOneWidget);
        expect(
            find.text(locale == 'en'
                ? '-51.500800, -0.124700'
                : '-51,500800; -0,124700'),
            findsOneWidget);
        expect(find.text(locale == 'en' ? 'Within 35 m' : 'Precisão de 35 m'),
            findsOneWidget);
        expect(find.text(locale == 'en' ? 'Altitude 30 m' : 'Altitude de 30 m'),
            findsOneWidget);
        expect(find.text(locale == 'en' ? 'Open in map' : 'Abrir no mapa'),
            findsOneWidget);
        expect(find.textContaining('geo:'), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(overrides.created, 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an invalid geo_uri says so ($locale)', (tester) async {
        await useLocale(locale);
        await pumpMessage(tester, room, {
          'msgtype': 'm.location',
          'body': 'Location javascript:alert(1)',
          'geo_uri': 'javascript:alert(1)',
        });

        expect(
            find.byKey(TimelineEventViewLocation.invalidKey), findsOneWidget);
        expect(
            find.text(locale == 'en'
                ? 'This location cannot be shown: its coordinates are not '
                    'valid'
                : 'Não é possível mostrar esta localização: as coordenadas '
                    'não são válidas'),
            findsOneWidget);
        expect(find.byKey(TimelineEventViewLocation.openMapKey), findsNothing);
        // The sender's text stays plain text: nothing in the card is a
        // link.
        expect(
            find.descendant(
                of: find.byKey(TimelineEventViewLocation.cardKey),
                matching: find.byWidgetPredicate((w) =>
                    w is RichText &&
                    !w.text.visitChildren((span) =>
                        span is! TextSpan || span.recognizer == null))),
            findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    test('sends a valid m.location', () async {
      transport.sentEvents.clear();
      final id = await room.sendLocation(
          MatrixLocationUri.fromInput('-23.5505, -46.6333')!,
          description: '  The coop  ');
      expect(id, isNotNull);
      expect(transport.sentEvents, hasLength(1));
      final content = transport.sentEvents.single;
      expect(content['msgtype'], matrix.MessageTypes.Location);
      expect(content['geo_uri'], 'geo:-23.5505,-46.6333');
      expect(content['body'], 'The coop');
      expect(content['org.matrix.msc3488.location'],
          {'uri': 'geo:-23.5505,-46.6333', 'description': 'The coop'});
      expect(content['org.matrix.msc3488.asset'], {'type': 'm.pin'});
      expect(MatrixLocationUri.tryParse(content['geo_uri']), isNotNull);
    });

    test('without a description, the body is the URI', () async {
      transport.sentEvents.clear();
      await room.sendLocation(MatrixLocationUri.tryParse('geo:10,20;u=5')!);
      final content = transport.sentEvents.single;
      expect(content['body'], 'geo:10,20;u=5');
      expect(content['geo_uri'], 'geo:10,20;u=5');
      expect(content['org.matrix.msc3488.location'], {'uri': 'geo:10,20;u=5'});
    });
  });

  group('composer form', () {
    Future<List<LocationToSend>> pumpForm(WidgetTester tester) async {
      final sent = <LocationToSend>[];
      await tester.pumpWidget(
          host(SendLocationForm(onSend: (place) => sent.add(place))));
      return sent;
    }

    FilledButton sendButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(SendLocationForm.sendKey));

    testWidgets('send waits for valid coordinates', (tester) async {
      await useLocale('en');
      final sent = await pumpForm(tester);
      expect(sendButton(tester).onPressed, isNull);

      await tester.enterText(
          find.byKey(SendLocationForm.coordinatesKey), 'javascript:alert(1)');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(sendButton(tester).onPressed, isNull);
      expect(find.textContaining('Type a latitude from -90 to 90'),
          findsOneWidget);
      expect(sent, isEmpty);

      await tester.enterText(
          find.byKey(SendLocationForm.coordinatesKey), '-23.5505, -46.6333');
      await tester.enterText(
          find.byKey(SendLocationForm.descriptionKey), 'The coop');
      await tester.pump();
      await tester.tap(find.byKey(SendLocationForm.sendKey));
      await tester.pump();

      expect(sent, hasLength(1));
      expect(sent.single.location.geoUri, 'geo:-23.5505,-46.6333');
      expect(sent.single.description, 'The coop');
    });

    testWidgets('reads in Portuguese', (tester) async {
      await useLocale('pt');
      await pumpForm(tester);
      expect(find.text('Coordenadas'), findsOneWidget);
      expect(find.text('Descrição (opcional)'), findsOneWidget);
      expect(find.text('Enviar'), findsOneWidget);
    });
  });
}
