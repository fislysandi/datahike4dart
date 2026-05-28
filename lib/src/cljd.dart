/// Functional, exception-throwing API for ClojureDart (and plain Dart) users.
///
/// This layer wraps [DatahikeClient] with a data-driven, exception-based
/// interface that feels natural from ClojureDart interop:
///
/// ```clojure
/// (require '["package:datahike4dart/datahike4dart.dart" :as dh])
///
/// (let [db (dh/open)]
///   (try
///     (let [cfg (dh/file-config "/tmp/my-db" "uuid" :write)]
///       (dh/create-db! db cfg)
///       (dh/transact! db cfg (dh/schema-tx
///                              [(dh/->SchemaAttribute ":name" :string :one)]))
///       (dh/transact! db cfg (dh/tx-data
///                              [(dh/entity-map {":name" (dh/edn-value "Alice")})]))
///       (println (dh/q db cfg "[:find ?e :where [?e :name ?n]]")))
///     (finally (dh/close db))))
/// ```
///
/// All functions ending in `!` mutate state. All functions throw
/// [DatahikeException] on failure (no `Either` monad).
library;

import 'datahike.dart';
import 'config.dart';
import 'tx.dart';
import 'tx.dart' as tx;

export 'datahike.dart' show DatahikeException;
export 'config.dart' show DatahikeConfig, SchemaFlexibility;
export 'tx.dart' show SchemaAttribute, ValueType, Cardinality, Uniqueness;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Opens a Datahike client.
///
/// Throws [DatahikeException] if the native library cannot be loaded.
DatahikeClient open({String? libraryPath}) {
  final result = DatahikeClient.open(libraryPath: libraryPath);
  if (result.isLeft()) {
    final failure = result.swap().getOrElse((_) =>
      const DatahikeNativeFailure('Unknown open failure'),
    );
    throw DatahikeException(failure.toString());
  }
  return result.getOrElse(
    (_) => throw DatahikeException('Unexpected open failure'),
  );
}

/// Closes the client and releases native resources.
void close(DatahikeClient db) => db.close();

// ---------------------------------------------------------------------------
// Config helpers
// ---------------------------------------------------------------------------

/// Builds a file-backed config EDN string.
String fileConfig(
  String path,
  String id, {
  SchemaFlexibility schemaFlexibility = SchemaFlexibility.write,
  bool keepHistory = false,
  String? initialTx,
}) => DatahikeConfig.file(
  path: path,
  id: id,
  schemaFlexibility: schemaFlexibility,
  keepHistory: keepHistory,
  initialTx: initialTx,
).toEdn();

/// Builds an in-memory config EDN string.
String memoryConfig(
  String id, {
  SchemaFlexibility schemaFlexibility = SchemaFlexibility.write,
  bool keepHistory = false,
  String? initialTx,
}) => DatahikeConfig.memory(
  id: id,
  schemaFlexibility: schemaFlexibility,
  keepHistory: keepHistory,
  initialTx: initialTx,
).toEdn();

// ---------------------------------------------------------------------------
// Database ops (mutating)
// ---------------------------------------------------------------------------

/// Creates a new database.
String createDb(DatahikeClient db, String configEdn) {
  final result = db.createDatabase(configEdn);
  if (result.isLeft()) {
    final failure = result.swap().getOrElse((_) =>
      const DatahikeNativeFailure('Unknown create failure'),
    );
    throw DatahikeException(failure.toString());
  }
  return result.getOrElse((_) => '');
}

/// Deletes the database.
String deleteDb(DatahikeClient db, String configEdn) {
  final result = db.deleteDatabase(configEdn);
  if (result.isLeft()) {
    final failure = result.swap().getOrElse((_) =>
      const DatahikeNativeFailure('Unknown delete failure'),
    );
    throw DatahikeException(failure.toString());
  }
  return result.getOrElse((_) => '');
}

/// Returns true if the database exists.
bool dbExists(DatahikeClient db, String configEdn) {
  final result = db.databaseExists(configEdn);
  if (result.isLeft()) {
    final failure = result.swap().getOrElse((_) =>
      const DatahikeNativeFailure('Unknown exists failure'),
    );
    throw DatahikeException(failure.toString());
  }
  return result.getOrElse((_) => false);
}

/// Transacts [txData] into the database.
String transact(DatahikeClient db, String configEdn, String txData) {
  final result = db.transact(configEdn, txData);
  if (result.isLeft()) {
    final failure = result.swap().getOrElse((_) =>
      const DatahikeNativeFailure('Unknown transact failure'),
    );
    throw DatahikeException(failure.toString());
  }
  return result.getOrElse((_) => '');
}

// ---------------------------------------------------------------------------
// Query / read
// ---------------------------------------------------------------------------

/// Runs a Datalog query. Returns raw EDN result.
String q(DatahikeClient db, String configEdn, String queryEdn) {
  final result = db.q(queryEdn, [DatahikeInput.database(configEdn)]);
  if (result.isLeft()) {
    final failure = result.swap().getOrElse((_) =>
      const DatahikeNativeFailure('Unknown query failure'),
    );
    throw DatahikeException(failure.toString());
  }
  return result.getOrElse((_) => '');
}

/// Runs a Datalog query and returns rows as a Dart List.
List<List<Object?>> qRows(
  DatahikeClient db,
  String configEdn,
  String queryEdn,
) {
  final result = db.qRows(queryEdn, [DatahikeInput.database(configEdn)]);
  if (result.isLeft()) {
    final failure = result.swap().getOrElse((_) =>
      const DatahikeNativeFailure('Unknown query failure'),
    );
    throw DatahikeException(failure.toString());
  }
  return result.getOrElse((_) => []);
}

/// Pulls attributes for entity [eid]. Returns raw EDN.
String pull(DatahikeClient db, String configEdn, String selectorEdn, int eid) {
  final result = db.pull(DatahikeInput.database(configEdn), selectorEdn, eid);
  if (result.isLeft()) {
    final failure = result.swap().getOrElse((_) =>
      const DatahikeNativeFailure('Unknown pull failure'),
    );
    throw DatahikeException(failure.toString());
  }
  return result.getOrElse((_) => '');
}

/// Returns the entity map for [eid].
Map<Object?, Object?>? entity(DatahikeClient db, String configEdn, int eid) {
  final result = db.entityMap(DatahikeInput.database(configEdn), eid);
  if (result.isLeft()) {
    final failure = result.swap().getOrElse((_) =>
      const DatahikeNativeFailure('Unknown entity failure'),
    );
    throw DatahikeException(failure.toString());
  }
  return result.getOrElse((_) => null);
}

/// Returns the schema as raw EDN.
String schema(DatahikeClient db, String configEdn) {
  final result = db.schema(DatahikeInput.database(configEdn));
  if (result.isLeft()) {
    final failure = result.swap().getOrElse((_) =>
      const DatahikeNativeFailure('Unknown schema failure'),
    );
    throw DatahikeException(failure.toString());
  }
  return result.getOrElse((_) => '');
}

/// Returns all datoms for the given [index] (e.g. ':eavt').
List<List<Object?>> datoms(DatahikeClient db, String configEdn, String index) {
  final result = db.datomsList(DatahikeInput.database(configEdn), index);
  if (result.isLeft()) {
    final failure = result.swap().getOrElse((_) =>
      const DatahikeNativeFailure('Unknown datoms failure'),
    );
    throw DatahikeException(failure.toString());
  }
  return result.getOrElse((_) => []);
}

// ---------------------------------------------------------------------------
// Transaction helpers
// ---------------------------------------------------------------------------

/// Alias for [dbAdd] from the tx module.
String dbAdd({required int eid, required String attr, required String value}) =>
    tx.dbAdd(eid: eid, attr: attr, value: value);

/// Alias for [dbRetract] from the tx module.
String dbRetract({
  required int eid,
  required String attr,
  required String value,
}) => tx.dbRetract(eid: eid, attr: attr, value: value);

/// Alias for [ednValue] from the tx module.
String ednValue(Object? value) => tx.ednValue(value);

/// Alias for [txData] from the tx module.
String txData(List<String> operations) => tx.txData(operations);

/// Alias for [schemaTx] from the tx module.
String schemaTx(List<SchemaAttribute> attributes) => tx.schemaTx(attributes);

/// Alias for [entityMap] from the tx module.
String entityMap(Map<String, String> attrs) => tx.entityMap(attrs);
