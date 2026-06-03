import 'dart:io';
import 'package:datahike4dart/datahike4dart.dart';

void main() {
  final parentDir = Directory.systemTemp.createTempSync('renfin_raw_test_');
  final dbPath = '${parentDir.path}/db';
  final config = DatahikeConfig.file(
    path: dbPath,
    id: 'b2c3d4e5-0000-0000-0000-000000000001',
    schemaFlexibility: SchemaFlexibility.read,
    keepHistory: true,
  ).toEdn();

  final openResult = DatahikeClient.open();
  openResult.match(
    (failure) { print('OPEN FAILED: ${failure.message}'); exit(1); },
    (datahike) {
      try {
        datahike.createDatabase(config);
        datahike.transact(config, '''
[{:db/ident :account/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
 {:db/ident :account/balance :db/valueType :db.type/bigdec :db/cardinality :db.cardinality/one}
 {:db/ident :account/currency :db/valueType :db.type/keyword :db/cardinality :db.cardinality/one}]
''');
        datahike.transact(config, '''
[{:account/name "Checking" :account/balance 5000.00M :account/currency :USD}
 {:account/name "Savings" :account/balance 12000.50M :account/currency :USD}]
''');

        // Raw query — returns EDN string without parsing
        final input = DatahikeInput.database(config);
        final rawResult = datahike.q(
          '[:find ?name ?bal ?curr :where [?e :account/name ?name] [?e :account/balance ?bal] [?e :account/currency ?curr]]',
          [input],
        );
        rawResult.match(
          (f) => print('RAW QUERY FAILED: ${f.message}'),
          (edn) => print('Raw EDN output (bigdec values):\n$edn'),
        );

        // JSON output — bypasses EDN parsing entirely
        final jsonResult = datahike.q(
          '[:find ?name ?bal ?curr :where [?e :account/name ?name] [?e :account/balance ?bal] [?e :account/currency ?curr]]',
          [input],
          outputFormat: DatahikeFormat.json,
        );
        jsonResult.match(
          (f) => print('JSON QUERY FAILED: ${f.message}'),
          (json) => print('\nJSON output (bigdec values):\n$json'),
        );
      } finally {
        datahike.deleteDatabase(config);
        datahike.close();
        if (parentDir.existsSync()) parentDir.deleteSync(recursive: true);
      }
    },
  );
}
