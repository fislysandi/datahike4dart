/// Dart FFI bindings for [Datahike](https://datahike.io/), a durable Datalog
/// database.
///
/// Two API layers are provided:
///
/// **1. [DatahikeClient] (recommended)** — Functional API using `fpdart`
/// `Either<DatahikeFailure, T>` results. Every operation returns an `Either`
/// for explicit error handling without exceptions.
///
/// ```dart
/// final result = DatahikeClient.open().flatMap((datahike) {
///   return datahike.qRows(
///     '[:find ?e :where [?e :name ?name]]',
///     [DatahikeInput.database(config)],
///   );
/// });
///
/// result.match(
///   (failure) => print('Error: ${failure.message}'),
///   (rows) => print('Found $rows'),
/// );
/// ```
///
/// **2. [Datahike] (raw FFI)** — Lower-level bindings via `Datahike.openRaw()`.
/// Throws [DatahikeException] on failure. Useful for tests or when you want
/// try/catch error handling.
///
/// **3. [DatahikeIsolate] (async)** — Runs the native library in a dedicated
/// worker isolate so queries do not block the Flutter UI thread.
///
/// ```dart
/// final service = await DatahikeIsolate.start();
/// final rows = await service.qRows('[:find ?e :where [?e :name ?name]]', [...]);
/// await service.close();
/// ```
///
/// See also:
/// - [DatahikeConfig] for typed config builders
/// - [SchemaAttribute] for schema definitions
/// - [doc/clojuredart.md](doc/clojuredart.md) for ClojureDart usage
library;

export 'src/config.dart';
export 'src/datahike.dart';
export 'src/edn.dart';
export 'src/isolate.dart';
export 'src/tx.dart';
