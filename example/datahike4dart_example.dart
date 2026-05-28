import 'package:datahike4dart/datahike4dart.dart';

void main() {
  final config = DatahikeConfig.file(
    path: '/tmp/datahike4dart-example',
    id: 'f11e0000-0000-0000-0000-000000000001',
    schemaFlexibility: SchemaFlexibility.write,
  ).toEdn();

  final result = DatahikeClient.open().flatMap((datahike) {
    datahike.createDatabase(config);

    // Define schema using typed builders.
    datahike.transact(
      config,
      schemaTx([
        const SchemaAttribute(
          ident: ':name',
          valueType: ValueType.string,
          cardinality: Cardinality.one,
        ),
      ]),
    );

    // Insert data using map-form transactions.
    datahike.transact(
      config,
      txData([
        entityMap({':name': ednValue('Alice')}),
      ]),
    );

    // Query with typed result decoding.
    final queryResult = datahike.qRows(
      '[:find ?e ?name :where [?e :name ?name]]',
      [DatahikeInput.database(config)],
    );
    datahike.close();
    return queryResult;
  });

  result.match(
    (failure) => print('Datahike failed: ${failure.message}'),
    (rows) => print('Found ${rows.length} rows: $rows'),
  );
}
