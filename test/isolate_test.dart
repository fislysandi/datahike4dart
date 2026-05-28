@Tags(['isolate'])
library;

import 'dart:io';

import 'package:datahike4dart/datahike4dart.dart';
import 'package:test/test.dart';

void main() {
  group('DatahikeIsolate', () {
    test('create, transact, and query in worker isolate', () async {
      final parentDir = Directory.systemTemp.createTempSync(
        'datahike4dart_isolate_test_',
      );
      final dbPath = '${parentDir.path}/db';
      final config = DatahikeConfig.file(
        path: dbPath,
        id: 'f11e0000-0000-0000-0000-000000000004',
        schemaFlexibility: SchemaFlexibility.write,
      ).toEdn();

      final service = await DatahikeIsolate.start();
      try {
        final create = await service.createDatabase(config);
        expect(create.isRight(), isTrue);

        final exists = await service.databaseExists(config);
        expect(exists.getOrElse((_) => false), isTrue);

        final schemaTxResult = await service.transact(
          config,
          schemaTx([
            const SchemaAttribute(
              ident: ':name',
              valueType: ValueType.string,
              cardinality: Cardinality.one,
            ),
          ]),
        );
        expect(schemaTxResult.isRight(), isTrue);

        final dataTx = await service.transact(
          config,
          txData([
            entityMap({':name': ednValue('Alice')}),
          ]),
        );
        expect(dataTx.isRight(), isTrue);

        final query = await service.q(
          '[:find ?e ?name :where [?e :name ?name]]',
          [DatahikeInput.database(config)],
        );
        expect(query.isRight(), isTrue);
        expect(query.getOrElse((_) => ''), contains('Alice'));
      } finally {
        await service.close();
        if (parentDir.existsSync()) {
          parentDir.deleteSync(recursive: true);
        }
      }
    });

    test(
      'sequential async calls work and do not block the event loop',
      () async {
        final parentDir = Directory.systemTemp.createTempSync(
          'datahike4dart_isolate_test_',
        );
        final dbPath = '${parentDir.path}/db';
        final config = DatahikeConfig.file(
          path: dbPath,
          id: 'f11e0000-0000-0000-0000-000000000005',
          schemaFlexibility: SchemaFlexibility.write,
        ).toEdn();

        final service = await DatahikeIsolate.start();
        try {
          await service.createDatabase(config);

          final schemaTxResult = await service.transact(
            config,
            schemaTx([
              const SchemaAttribute(
                ident: ':item/name',
                valueType: ValueType.string,
                cardinality: Cardinality.one,
              ),
            ]),
          );
          expect(schemaTxResult.isRight(), isTrue);

          final dataTx = await service.transact(
            config,
            txData([
              entityMap({':item/name': ednValue('A')}),
              entityMap({':item/name': ednValue('B')}),
            ]),
          );
          expect(dataTx.isRight(), isTrue);

          // Two sequential queries — each runs in the worker isolate.
          final r1 = await service.q(
            '[:find ?e . :where [?e :item/name "A"]]',
            [DatahikeInput.database(config)],
          );
          expect(r1.isRight(), isTrue);

          final r2 = await service.q(
            '[:find ?e . :where [?e :item/name "B"]]',
            [DatahikeInput.database(config)],
          );
          expect(r2.isRight(), isTrue);
        } finally {
          await service.close();
          if (parentDir.existsSync()) {
            parentDir.deleteSync(recursive: true);
          }
        }
      },
    );

    test('closed service returns failure', () async {
      final service = await DatahikeIsolate.start();
      await service.close();

      final result = await service.q('[:find ?e :where [?e :name ?name]]', [
        DatahikeInput.edn('{:dummy "value"}'),
      ]);
      expect(result.isLeft(), isTrue);
    });
  });
}
