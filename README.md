# datahike4dart

Dart FFI bindings for [Datahike](https://datahike.io/), a durable Datalog database.

## Overview

Datahike is a durable, embeddable Datalog database inspired by Datomic and DataScript. This package provides Dart bindings to Datahike's native C library (`libdatahike`) via `dart:ffi`, enabling Dart CLI/server and Flutter desktop apps to use Datahike as a local database.

## Features

- **Database lifecycle**: create, delete, and check database existence
- **Data writes**: transact data and merge databases
- **Data queries**: execute Datalog queries, pull entities, and read entities
- **Indexes and metadata**: access schema, reverse schema, metrics, and index data
- **Versioning**: read commits, branches, parent commit ids, and run storage GC
- **Functional API**: `fpdart` `Either<DatahikeFailure, T>` results for explicit error handling

## Native library requirement

You need Datahike's native library on your machine:

- Linux: `libdatahike.so`
- macOS: `libdatahike.dylib`
- Windows: `datahike.dll`

Build it from the Datahike repository or download a matching release artifact. See [native build notes](doc/native-build.md).

Then either:

```bash
export DATAHIKE_LIB=/absolute/path/to/libdatahike.so
```

or pass `libraryPath` to `DatahikeClient.open()`.

## Quick start

```dart
import 'package:datahike4dart/datahike4dart.dart';

void main() {
  const config = '{:store {:backend :file :path "/tmp/datahike4dart" '
      ':id #uuid "f11e0000-0000-0000-0000-000000000001"} '
      ':schema-flexibility :write}';

  final result = DatahikeClient.open().flatMap((datahike) {
    final queryResult = datahike
        .createDatabase(config)
        .flatMap((_) => datahike.transact(config,
            '[{:db/ident :name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}]'))
        .flatMap((_) => datahike.transact(config, '[{:name "Alice"}]'))
        .flatMap((_) => datahike.q(
              '[:find ?e ?name :where [?e :name ?name]]',
              [DatahikeInput.database(config)],
            ));
    datahike.close();
    return queryResult;
  });

  result.match(
    (failure) => print('Datahike failed: ${failure.message}'),
    (edn) => print(edn), // e.g. #{[2 "Alice"]}
  );
}
```

## API layers

### `DatahikeClient` — recommended

Functional-first API using `fpdart`:

- `DatahikeClient.open()` returns `Either<DatahikeFailure, DatahikeClient>`.
- Operations return `Either<DatahikeFailure, T>`.
- Native failures are represented as typed failures such as `DatahikeLoadFailure`, `DatahikeNativeFailure`, `DatahikeClosedFailure`, and `DatahikeInvalidInputFailure`.

### `Datahike` — raw FFI

Lower-level direct FFI bindings are available via `Datahike.openRaw()`. This layer may throw `DatahikeException` and is mainly for tests or advanced users.

## Platform support

- ✅ Linux x64: create/transact/query integration tested with Datahike `libdatahike-0.8.1689-linux-amd64`.
- 🟡 macOS/Windows desktop: expected to work with matching native release artifacts; not yet verified here.
- 🟡 Android/iOS: planned after desktop; Dart FFI is suitable, but native Datahike cross-compilation/packaging still needs proof.
- ❌ Web: not supported by this FFI approach.

See [mobile support notes](doc/mobile.md).

## Testing

Unit tests do not require the native library:

```bash
dart test
```

Native integration tests require `DATAHIKE_LIB`:

```bash
DATAHIKE_LIB=/absolute/path/to/libdatahike.so dart test test/native_integration_test.dart
```

## License

MIT.
