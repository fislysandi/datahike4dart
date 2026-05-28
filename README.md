# datahike4dart

Dart bindings for [Datahike](https://datahike.io/) through Datahike's native C library (`libdatahike`).

Datahike is a durable Datalog database inspired by Datomic/DataScript. This package exposes the native Datahike API to Dart using `dart:ffi`.

## Status

Early binding layer. It currently wraps the core native functions exposed by Datahike's `libdatahike`:

- database lifecycle: `createDatabase`, `deleteDatabase`, `databaseExists`
- writes: `transact`, `mergeDb`
- queries: `q`, `pull`, `pullMany`, `entity`
- indexes/metadata: `datoms`, `seekDatoms`, `indexRange`, `schema`, `reverseSchema`, `metrics`
- versioning: `commitId`, `parentCommitIds`, `branch`, `branches`, `deleteBranch`, `gcStorage`

The wrapper sends and receives EDN strings by default. JSON/CBOR are supported by the native API too, but EDN is the most complete representation for Datahike keywords, UUIDs, sets, and query forms.

## Native library requirement

You need Datahike's native library on your machine:

- Linux: `libdatahike.so`
- macOS: `libdatahike.dylib`
- Windows: `datahike.dll`

Build it from the Datahike repository with GraalVM/native-image, for example:

```bash
git clone https://github.com/replikativ/datahike.git
cd datahike
bb ni-compile
```

Then either:

```bash
export DATAHIKE_LIB=/absolute/path/to/libdatahike.so
```

or pass `libraryPath` to `Datahike.open()`.

## Example

```dart
import 'package:datahike4dart/datahike4dart.dart';

void main() {
  const config = '{:store {:backend :file :path "/tmp/datahike4dart" '
      ':id #uuid "f11e0000-0000-0000-0000-000000000001"} '
      ':schema-flexibility :write}';

  final result = DatahikeClient.open().flatMap((datahike) {
    datahike.createDatabase(config);
    datahike.transact(config,
        '[{:db/ident :name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}]');
    datahike.transact(config, '[{:name "Alice"}]');

    final queryResult = datahike.q(
      '[:find ?e ?name :where [?e :name ?name]]',
      [DatahikeInput.database(config)],
    );
    datahike.close();
    return queryResult;
  });

  result.match(
    (failure) => print('Datahike failed: ${failure.message}'),
    (edn) => print(edn), // e.g. #{[2 "Alice"]}
  );
}
```

## API style

The preferred public API is functional-first and uses `fpdart`:

- `DatahikeClient.open()` returns `Either<DatahikeFailure, DatahikeClient>`.
- Operations return `Either<DatahikeFailure, T>`.
- Native Datahike errors are represented as typed failures such as `DatahikeLoadFailure` and `DatahikeNativeFailure`.

The lower-level raw FFI client is available as `Datahike.openRaw()` for tests and advanced use. It may throw `DatahikeException` when native Datahike returns an `exception:` response.

## Platform scope

MVP target: Dart CLI/server and Flutter desktop on native platforms that can load Datahike's native library.

Mobile target: Android/iOS will be investigated after desktop works. The Dart FFI layer is suitable for mobile, but Datahike native library cross-compilation and packaging still need proof.

Not supported by this FFI package: Flutter Web / Dart Web.
