import 'dart:io';

import 'package:datahike4dart/datahike4dart.dart';
import 'package:test/test.dart';

void main() {
  final nativeLibrary = Platform.environment['DATAHIKE_LIB'];
  final hasNativeLibrary = nativeLibrary != null && nativeLibrary.isNotEmpty;

  group('native Datahike integration', () {
    test(
      'create, transact, and query',
      skip: hasNativeLibrary
          ? false
          : 'Set DATAHIKE_LIB to run native integration tests.',
      () {
        final parentDir = Directory.systemTemp.createTempSync(
          'datahike4dart_test_',
        );
        final dbPath = '${parentDir.path}/db';
        final config =
            '{:store {:backend :file :path "$dbPath" '
            ':id #uuid "f11e0000-0000-0000-0000-000000000001"} '
            ':schema-flexibility :write}';

        final openResult = DatahikeClient.open(libraryPath: nativeLibrary);
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
              ':db/cardinality :db.cardinality/one}]',
            );
            expect(
              schemaTx.isRight(),
              isTrue,
              reason: schemaTx.match(
                (failure) => failure.toString(),
                (_) => '',
              ),
            );
            final dataTx = datahike.transact(config, '[{:name "Alice"}]');
            expect(
              dataTx.isRight(),
              isTrue,
              reason: dataTx.match((failure) => failure.toString(), (_) => ''),
            );

            final query = datahike.q(
              '[:find ?e ?name :where [?e :name ?name]]',
              [DatahikeInput.database(config)],
            );
            expect(
              query.isRight(),
              isTrue,
              reason: query.match((failure) => failure.toString(), (_) => ''),
            );
            expect(query.getOrElse((_) => ''), contains('Alice'));
          } finally {
            datahike.deleteDatabase(config);
            datahike.close();
            if (parentDir.existsSync()) {
              parentDir.deleteSync(recursive: true);
            }
          }
        });
      },
    );
  });
}
