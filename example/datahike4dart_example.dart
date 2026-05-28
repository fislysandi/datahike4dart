import 'package:datahike4dart/datahike4dart.dart';

void main() {
  const config =
      '{:store {:backend :file :path "/tmp/datahike4dart-example" '
      ':id #uuid "f11e0000-0000-0000-0000-000000000001"} '
      ':schema-flexibility :write}';

  final result = DatahikeClient.open().flatMap((datahike) {
    datahike.createDatabase(config);
    datahike.transact(
      config,
      '[{:db/ident :name :db/valueType :db.type/string '
      ':db/cardinality :db.cardinality/one}]',
    );
    datahike.transact(config, '[{:name "Alice"}]');

    final queryResult = datahike.q('[:find ?e ?name :where [?e :name ?name]]', [
      DatahikeInput.database(config),
    ]);
    datahike.close();
    return queryResult;
  });

  result.match(
    (failure) => print('Datahike failed: ${failure.message}'),
    (edn) => print(edn),
  );
}
