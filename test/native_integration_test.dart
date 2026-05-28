import 'dart:io';

import 'package:datahike4dart/datahike4dart.dart';
import 'package:test/test.dart';

void main() {
  group('native Datahike integration', () {
    test('create, transact, and query', () {
      _withTestDb((datahike, config) {
        final query = datahike.q('[:find ?e ?name :where [?e :name ?name]]', [
          DatahikeInput.database(config),
        ]);
        expect(
          query.isRight(),
          isTrue,
          reason: query.match((failure) => failure.toString(), (_) => ''),
        );
        expect(query.getOrElse((_) => ''), contains('Alice'));
      });
    });

    test('pull and pullMany', () {
      _withTestDb((datahike, config) {
        final input = DatahikeInput.database(config);

        // Find Alice's entity id dynamically because schema attributes
        // consume the low entity ids.
        final eidResult = datahike.q('[:find ?e . :where [?e :name "Alice"]]', [
          input,
        ]);
        expect(eidResult.isRight(), isTrue);
        final aliceEid = int.parse(eidResult.getOrElse((_) => '0'));
        expect(aliceEid, greaterThan(0));

        final pullResult = datahike.pull(input, '[:name]', aliceEid);
        expect(
          pullResult.isRight(),
          isTrue,
          reason: pullResult.match((failure) => failure.toString(), (_) => ''),
        );
        expect(pullResult.getOrElse((_) => ''), contains('Alice'));

        final pullManyResult = datahike.pullMany(
          input,
          '[:name]',
          '[$aliceEid]',
        );
        expect(
          pullManyResult.isRight(),
          isTrue,
          reason: pullManyResult.match(
            (failure) => failure.toString(),
            (_) => '',
          ),
        );
      });
    });

    test('entity', () {
      _withTestDb((datahike, config) {
        final input = DatahikeInput.database(config);
        final eidResult = datahike.q('[:find ?e . :where [?e :name "Alice"]]', [
          input,
        ]);
        expect(eidResult.isRight(), isTrue);
        final aliceEid = int.parse(eidResult.getOrElse((_) => '0'));

        final entityResult = datahike.entity(input, aliceEid);
        expect(
          entityResult.isRight(),
          isTrue,
          reason: entityResult.match(
            (failure) => failure.toString(),
            (_) => '',
          ),
        );
        expect(entityResult.getOrElse((_) => ''), contains('Alice'));
      });
    });

    test('schema and reverseSchema', () {
      _withTestDb((datahike, config) {
        final schemaResult = datahike.schema(DatahikeInput.database(config));
        expect(
          schemaResult.isRight(),
          isTrue,
          reason: schemaResult.match(
            (failure) => failure.toString(),
            (_) => '',
          ),
        );
        expect(schemaResult.getOrElse((_) => ''), contains(':name'));

        final reverseResult = datahike.reverseSchema(
          DatahikeInput.database(config),
        );
        expect(
          reverseResult.isRight(),
          isTrue,
          reason: reverseResult.match(
            (failure) => failure.toString(),
            (_) => '',
          ),
        );
      });
    });

    test('datoms and seekDatoms', () {
      _withTestDb((datahike, config) {
        final datomsResult = datahike.datoms(
          DatahikeInput.database(config),
          ':eavt',
        );
        expect(
          datomsResult.isRight(),
          isTrue,
          reason: datomsResult.match(
            (failure) => failure.toString(),
            (_) => '',
          ),
        );
        expect(datomsResult.getOrElse((_) => ''), contains('Alice'));

        final seekResult = datahike.seekDatoms(
          DatahikeInput.database(config),
          ':eavt',
        );
        expect(
          seekResult.isRight(),
          isTrue,
          reason: seekResult.match((failure) => failure.toString(), (_) => ''),
        );
      });
    });

    test('branches', () {
      _withTestDb((datahike, config) {
        final branchesResult = datahike.branches(config);
        expect(
          branchesResult.isRight(),
          isTrue,
          reason: branchesResult.match(
            (failure) => failure.toString(),
            (_) => '',
          ),
        );
        // Datahike default branch name is :db on some versions.
        final value = branchesResult.getOrElse((_) => '');
        expect(value.isNotEmpty, isTrue);
      });
    });

    test('concurrent clients do not clobber output', () {
      // Verify the _CallbackCapture singleton fix: two simultaneous
      // DatahikeClient instances should not corrupt each other's results.
      _withTestDb((datahikeA, configA) {
        final parentDirB = Directory.systemTemp.createTempSync(
          'datahike4dart_test_',
        );
        final dbPathB = '${parentDirB.path}/db';
        final configB = DatahikeConfig.file(
          path: dbPathB,
          id: 'f11e0000-0000-0000-0000-000000000002',
          schemaFlexibility: SchemaFlexibility.write,
        ).toEdn();

        final openB = DatahikeClient.open();
        openB.match((failure) => fail(failure.toString()), (datahikeB) {
          try {
            final createB = datahikeB.createDatabase(configB);
            expect(createB.isRight(), isTrue);
            final existsB = datahikeB.databaseExists(configB);
            expect(existsB.getOrElse((_) => false), isTrue);

            // Interleave queries on both databases.
            final queryA = datahikeA.q(
              '[:find ?e . :where [?e :name "Alice"]]',
              [DatahikeInput.database(configA)],
            );
            final queryB = datahikeB.q(
              '[:find ?e . :where [?e :name "Alice"]]',
              [DatahikeInput.database(configB)],
            );

            expect(queryA.isRight(), isTrue);
            expect(queryB.isRight(), isTrue);
            // Alice is in A but not in B.
            expect(
              queryA.getOrElse((_) => ''),
              isNot(equals(queryB.getOrElse((_) => ''))),
            );
          } finally {
            datahikeB.deleteDatabase(configB);
            datahikeB.close();
            if (parentDirB.existsSync()) {
              parentDirB.deleteSync(recursive: true);
            }
          }
        });
      });
    });

    test('typed helpers decode native output', () {
      _withTestDb((datahike, config) {
        final input = DatahikeInput.database(config);

        // qRows
        final rowsResult = datahike.qRows(
          '[:find ?e ?name :where [?e :name ?name]]',
          [input],
        );
        expect(rowsResult.isRight(), isTrue);
        final rows = rowsResult.getOrElse((_) => []);
        expect(rows.length, 2); // Alice and Bob
        final names = rows.map((r) => r[1] as String).toSet();
        expect(names, contains('Alice'));
        expect(names, contains('Bob'));

        // pullMap
        final eidResult = datahike.q('[:find ?e . :where [?e :name "Alice"]]', [
          input,
        ]);
        expect(eidResult.isRight(), isTrue);
        final aliceEid = int.parse(eidResult.getOrElse((_) => '0'));

        final mapResult = datahike.pullMap(input, '[:name :age]', aliceEid);
        expect(mapResult.isRight(), isTrue);
        final map = mapResult.getOrElse((_) => null);
        expect(map, isNotNull);
        expect(map![':name'], 'Alice');
        expect(map[':age'], 30);

        // entityMap
        final entityResult = datahike.entityMap(input, aliceEid);
        expect(entityResult.isRight(), isTrue);
        final entity = entityResult.getOrElse((_) => null);
        expect(entity, isNotNull);
        expect(entity![':name'], 'Alice');

        // datomsList + Datom
        final datomsResult = datahike.datomsList(input, ':eavt');
        expect(datomsResult.isRight(), isTrue);
        final datomRows = datomsResult.getOrElse((_) => []);
        expect(datomRows.isNotEmpty, isTrue);
        final datoms = datomRows.map(Datom.fromRow).toList();
        expect(datoms.any((d) => d.a == ':name' && d.v == 'Alice'), isTrue);
      });
    });

    test('schema and entity builders work end-to-end', () {
      final parentDir = Directory.systemTemp.createTempSync(
        'datahike4dart_test_',
      );
      final dbPath = '${parentDir.path}/db';
      final config = DatahikeConfig.file(
        path: dbPath,
        id: 'f11e0000-0000-0000-0000-000000000003',
        schemaFlexibility: SchemaFlexibility.write,
      ).toEdn();

      final openResult = DatahikeClient.open();
      openResult.match((failure) => fail(failure.toString()), (datahike) {
        try {
          expect(datahike.createDatabase(config).isRight(), isTrue);

          final schemaTxResult = datahike.transact(
            config,
            schemaTx([
              const SchemaAttribute(
                ident: ':person/name',
                valueType: ValueType.string,
                cardinality: Cardinality.one,
              ),
              const SchemaAttribute(
                ident: ':person/age',
                valueType: ValueType.long,
                cardinality: Cardinality.one,
              ),
            ]),
          );
          expect(schemaTxResult.isRight(), isTrue);

          final dataTx = datahike.transact(
            config,
            txData([
              entityMap({
                ':person/name': ednValue('Carol'),
                ':person/age': ednValue(28),
              }),
              entityMap({
                ':person/name': ednValue('Dave'),
                ':person/age': ednValue(35),
              }),
            ]),
          );
          expect(dataTx.isRight(), isTrue);

          final rowsResult = datahike.qRows(
            '[:find ?e ?name :where [?e :person/name ?name]]',
            [DatahikeInput.database(config)],
          );
          expect(rowsResult.isRight(), isTrue);
          final rows = rowsResult.getOrElse((_) => []);
          expect(rows.length, 2);
          final names = rows.map((r) => r[1] as String).toSet();
          expect(names, contains('Carol'));
          expect(names, contains('Dave'));
        } finally {
          datahike.deleteDatabase(config);
          datahike.close();
          if (parentDir.existsSync()) {
            parentDir.deleteSync(recursive: true);
          }
        }
      });
    });

    test('metrics, commitId, parentCommitIds', () {
      _withTestDb((datahike, config) {
        final input = DatahikeInput.database(config);

        final metricsResult = datahike.metrics(input);
        expect(metricsResult.isRight(), isTrue);

        final commitResult = datahike.commitId(input);
        expect(commitResult.isRight(), isTrue);
        expect(commitResult.getOrElse((_) => '').isNotEmpty, isTrue);

        final parentResult = datahike.parentCommitIds(input);
        expect(parentResult.isRight(), isTrue);
      });
    });

    test('indexRange', () {
      _withTestDb((datahike, config) {
        final input = DatahikeInput.database(config);
        final result = datahike.indexRange(input, ':name', '"Alice"', '"Bob"');
        expect(result.isRight(), isTrue);
      });
    });

    test('branch, deleteBranch, mergeDb', () {
      _withTestDb((datahike, config) {
        // Create a branch.
        final branchResult = datahike.branch(config, ':db', ':experiment');
        expect(branchResult.isRight(), isTrue);

        final branchesResult = datahike.branches(config);
        expect(branchesResult.isRight(), isTrue);
        final branches = branchesResult.getOrElse((_) => '');
        expect(branches.contains(':experiment'), isTrue);

        // Delete the branch.
        final deleteResult = datahike.deleteBranch(config, ':experiment');
        expect(deleteResult.isRight(), isTrue);
      });
    });

    test('JSON output format', () {
      _withTestDb((datahike, config) {
        final input = DatahikeInput.database(config);
        final result = datahike.q(
          '[:find ?e ?name :where [?e :name ?name]]',
          [input],
          outputFormat: DatahikeFormat.json,
        );
        expect(result.isRight(), isTrue);
        final json = result.getOrElse((_) => '');
        expect(json.startsWith('[') || json.startsWith('{'), isTrue);
      });
    });
  });
}

void _withTestDb(void Function(DatahikeClient datahike, String config) test) {
  final parentDir = Directory.systemTemp.createTempSync('datahike4dart_test_');
  final dbPath = '${parentDir.path}/db';
  final config = DatahikeConfig.file(
    path: dbPath,
    id: 'f11e0000-0000-0000-0000-000000000001',
    schemaFlexibility: SchemaFlexibility.write,
  ).toEdn();

  final openResult = DatahikeClient.open();
  openResult.match((failure) => fail(failure.toString()), (datahike) {
    try {
      final create = datahike.createDatabase(config);
      expect(
        create.isRight(),
        isTrue,
        reason: create.match((failure) => failure.toString(), (_) => ''),
      );
      final exists = datahike.databaseExists(config);
      expect(
        exists.getOrElse((_) => false),
        isTrue,
        reason: exists.match((failure) => failure.toString(), (_) => ''),
      );
      final schemaTx = datahike.transact(
        config,
        '[{:db/ident :name :db/valueType :db.type/string '
        ':db/cardinality :db.cardinality/one '
        ':db/unique :db.unique/identity} '
        '{:db/ident :age :db/valueType :db.type/long '
        ':db/cardinality :db.cardinality/one}]',
      );
      expect(
        schemaTx.isRight(),
        isTrue,
        reason: schemaTx.match((failure) => failure.toString(), (_) => ''),
      );
      final dataTx = datahike.transact(
        config,
        '[{:name "Alice" :age 30} '
        '{:name "Bob" :age 25}]',
      );
      expect(
        dataTx.isRight(),
        isTrue,
        reason: dataTx.match((failure) => failure.toString(), (_) => ''),
      );

      test(datahike, config);
    } finally {
      datahike.deleteDatabase(config);
      datahike.close();
      if (parentDir.existsSync()) {
        parentDir.deleteSync(recursive: true);
      }
    }
  });
}
