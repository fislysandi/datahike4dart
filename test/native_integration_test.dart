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
        final dir = Directory.systemTemp.createTempSync('datahike4dart_test_');
        final config =
            '{:store {:backend :file :path "${dir.path}" '
            ':id #uuid "f11e0000-0000-0000-0000-000000000001"} '
            ':schema-flexibility :write}';

        final openResult = DatahikeClient.open(libraryPath: nativeLibrary);
        openResult.match((failure) => fail(failure.toString()), (datahike) {
          try {
            expect(datahike.createDatabase(config).isRight(), isTrue);
            expect(
              datahike.databaseExists(config).getOrElse((_) => false),
              isTrue,
            );
            expect(
              datahike
                  .transact(
                    config,
                    '[{:db/ident :name :db/valueType :db.type/string '
                    ':db/cardinality :db.cardinality/one}]',
                  )
                  .isRight(),
              isTrue,
            );
            expect(
              datahike.transact(config, '[{:name "Alice"}]').isRight(),
              isTrue,
            );

            final query = datahike.q(
              '[:find ?e ?name :where [?e :name ?name]]',
              [DatahikeInput.database(config)],
            );
            expect(query.isRight(), isTrue);
            expect(query.getOrElse((_) => ''), contains('Alice'));
          } finally {
            datahike.deleteDatabase(config);
            datahike.close();
            dir.deleteSync(recursive: true);
          }
        });
      },
    );
  });
}
