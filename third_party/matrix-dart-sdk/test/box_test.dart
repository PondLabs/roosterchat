import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:matrix/src/database/sqflite_box.dart'
    if (dart.library.js_interop) 'package:matrix/src/database/indexeddb_box.dart';

void main() {
  group('Box tests', () {
    late BoxCollection collection;
    const Set<String> boxNames = {'cats', 'dogs'};
    const data = {'name': 'Fluffy', 'age': 2};
    const data2 = {'name': 'Loki', 'age': 4};
    Database? db;
    const isWeb = bool.fromEnvironment('dart.library.js_interop');
    setUp(() async {
      if (!isWeb) {
        db = await databaseFactoryFfi.openDatabase(':memory:');
      }
      collection = await BoxCollection.open(
        'testbox',
        boxNames,
        sqfliteDatabase: db,
        sqfliteFactory: isWeb ? null : databaseFactoryFfi,
      );
    });

    test('Box.put and Box.get', () async {
      final box = collection.openBox<Map>('cats');
      await box.put('fluffy', data);
      expect(await box.get('fluffy'), data);
      await box.clear();
    });

    test('Box.getAll', () async {
      final box = collection.openBox<Map>('cats');
      await box.put('fluffy', data);
      await box.put('loki', data2);
      expect(await box.getAll(['fluffy', 'loki']), [data, data2]);
      await box.clear();
    });

    test('Box.getAllKeys', () async {
      final box = collection.openBox<Map>('cats');
      await box.put('fluffy', data);
      await box.put('loki', data2);
      expect(await box.getAllKeys(), ['fluffy', 'loki']);
      await box.clear();
    });

    test('Box.getAllValues', () async {
      final box = collection.openBox<Map>('cats');
      await box.put('fluffy', data);
      await box.put('loki', data2);
      expect(await box.getAllValues(), {'fluffy': data, 'loki': data2});
      await box.clear();
    });

    test('Box.delete', () async {
      final box = collection.openBox<Map>('cats');
      await box.put('fluffy', data);
      await box.put('loki', data2);
      await box.delete('fluffy');
      expect(await box.get('fluffy'), null);
      await box.clear();
    });

    test('Box.delete in transaction', () async {
      final box = collection.openBox<Map>('cats');
      await box.put('fluffy', data);
      await box.put('loki', data2);
      await collection.transaction(() async {
        await box.delete('fluffy');
        expect(await box.get('fluffy'), null);
      });
      expect(await box.get('fluffy'), null);
      await box.clear();
    });

    test('Box.deleteAll', () async {
      final box = collection.openBox<Map>('cats');
      await box.put('fluffy', data);
      await box.put('loki', data2);
      await box.deleteAll(['fluffy', 'loki']);
      expect(await box.get('fluffy'), null);
      expect(await box.get('loki'), null);
      await box.clear();
    });

    test('Box.clear', () async {
      final box = collection.openBox<Map>('cats');
      await box.put('fluffy', data);
      await box.put('loki', data2);
      await box.clear();
      expect(await box.get('fluffy'), null);
      expect(await box.get('loki'), null);
    });

    // ROOSTER: `Room.postLoad` reads in a transaction, also from inside the
    // one a sync or a page of history is stored in.
    group('A transaction inside another', () {
      /// What the database holds, read by a collection that cached nothing.
      Future<Object?> stored(String key) async {
        final fresh = await BoxCollection.open(
          'testbox',
          boxNames,
          sqfliteDatabase: db,
          sqfliteFactory: isWeb ? null : databaseFactoryFfi,
        );
        try {
          return await fresh.openBox<Map>('cats').get(key);
        } finally {
          // On the VM it shares the database with [collection].
          if (isWeb) await fresh.close();
        }
      }

      test('keeps what the outer one writes after it', () async {
        final box = collection.openBox<Map>('cats');
        await collection.transaction(() async {
          await box.put('fluffy', data);
          await collection.transaction(() async {
            expect(await box.get('fluffy'), data);
          });
          await box.put('fluffy', data2);
          await box.put('loki', data2);
          await box.delete('loki');
        });
        expect(await stored('fluffy'), data2);
        expect(await stored('loki'), null);
        await box.clear();
      });

      test('stores what it wrote itself, with the outer one', () async {
        final box = collection.openBox<Map>('cats');
        await collection.transaction(() async {
          await collection.transaction(() async {
            await box.put('fluffy', data);
          });
          // Not before the outer one ends.
          expect(await stored('fluffy'), null);
        });
        expect(await stored('fluffy'), data);
        await box.clear();
      });

      test('reads the keys the outer one wrote and deleted', () async {
        final box = collection.openBox<Map>('cats');
        await box.put('fluffy', data);
        await box.put('loki', data2);
        // The keys were never listed: this reads them from the database.
        await collection.transaction(() async {
          await box.put('tom', data);
          await box.delete('loki');
          await collection.transaction(() async {
            expect(await box.getAllKeys(), unorderedEquals(['fluffy', 'tom']));
          });
        });
        expect(await box.getAllKeys(), unorderedEquals(['fluffy', 'tom']));
        await box.clear();
      });
    });

    test('A transaction that throws leaves the next writes working', () async {
      final box = collection.openBox<Map>('cats');
      await expectLater(
        collection.transaction(() async {
          await box.put('fluffy', data);
          throw StateError('given up');
        }),
        throwsStateError,
      );
      await box.put('felix', data2);
      await collection.transaction(() async => box.put('tiger', data));
      final fresh = await BoxCollection.open(
        'testbox',
        boxNames,
        sqfliteDatabase: db,
        sqfliteFactory: isWeb ? null : databaseFactoryFfi,
      );
      final cats = fresh.openBox<Map>('cats');
      expect(await cats.get('felix'), data2);
      expect(await cats.get('tiger'), data);
      if (isWeb) await fresh.close();
      await box.clear();
    });

    test('Box.close', () async {
      await collection.close();
    });

    test(
      'Collection.deleteDatabase',
      () async {
        await collection.deleteDatabase(
          db?.path ?? '',
          isWeb ? null : databaseFactoryFfi,
        );
      },
    );
  });
}
