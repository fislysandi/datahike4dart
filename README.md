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
- **Config builders**: immutable Dart objects instead of hand-written EDN strings
- **Native library resolver**: automatic discovery with clear error messages

## Native library installation

You need Datahike's native library on your machine. The easiest way is to fetch the official release artifact:

```bash
dart tool/fetch_datahike_native.dart
```

This downloads the matching `libdatahike` release for your platform into `.native/`. The resolver will find it automatically.

### Manual installation

If you prefer to manage the library yourself:

- Linux: `libdatahike.so`
- macOS: `libdatahike.dylib`
- Windows: `datahike.dll`

Then either set the environment variable:

```bash
export DATAHIKE_LIB=/absolute/path/to/libdatahike.so
```

or pass `libraryPath` to `DatahikeClient.open()`.

Build instructions are in [native build notes](doc/native-build.md).

## Quick start

```dart
import 'package:datahike4dart/datahike4dart.dart';

void main() {
  final config = DatahikeConfig.file(
    path: '/tmp/datahike4dart',
    id: 'f11e0000-0000-0000-0000-000000000001',
    schemaFlexibility: SchemaFlexibility.write,
  ).toEdn();

  final result = DatahikeClient.open().flatMap((datahike) {
    final queryResult = datahike
        .createDatabase(config)
        .flatMap((_) => datahike.transact(
              config,
              schemaTx([
                const SchemaAttribute(
                  ident: ':name',
                  valueType: ValueType.string,
                  cardinality: Cardinality.one,
                ),
              ]),
            ))
        .flatMap((_) => datahike.transact(
              config,
              txData([entityMap({':name': ednValue('Alice')})]),
            ))
        .flatMap((_) => datahike.qRows(
              '[:find ?e ?name :where [?e :name ?name]]',
              [DatahikeInput.database(config)],
            ));
    datahike.close();
    return queryResult;
  });

  result.match(
    (failure) => print('Datahike failed: ${failure.message}'),
    (rows) => print('Found ${rows.length} rows: $rows'),
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

### Config builders

Instead of writing EDN by hand, use the typed config builders:

```dart
final config = DatahikeConfig.file(
  path: '/tmp/my-db',
  id: 'f11e0000-0000-0000-0000-000000000001',
  schemaFlexibility: SchemaFlexibility.write,
  keepHistory: true,
).toEdn();
```

A raw EDN escape hatch is available via `DatahikeConfig.fromEdn(...)`.

### Transaction and schema builders

Safe schema and transaction generation:

```dart
final schema = schemaTx([
  const SchemaAttribute(
    ident: ':person/name',
    valueType: ValueType.string,
    cardinality: Cardinality.one,
    unique: Uniqueness.identity,
  ),
]);

final data = txData([
  entityMap({':person/name': ednValue('Alice'), ':person/age': ednValue(30)}),
]);
```

### Typed result helpers

Parse native EDN responses automatically:

```dart
final rows = datahike.qRows(
  '[:find ?e ?name :where [?e :name ?name]]',
  [DatahikeInput.database(config)],
); // Either<..., List<List<Object?>>>

final entity = datahike.entityMap(input, eid); // Either<..., Map?>

final datoms = datahike.datomsList(input, ':eavt'); // Either<..., List<List<Object?>>>
```

Raw EDN methods (`q`, `pull`, `entity`, `datoms`) remain available.

## Native library resolution

The resolver searches for `libdatahike` in this order:

1. Explicit `libraryPath` argument (no fallback if missing)
2. `DATAHIKE_LIB` environment variable
3. App-local conventional paths (`.native/` under the current working directory)
4. Platform dynamic-loader default name

When the library cannot be found, `DatahikeClient.open()` returns a `DatahikeLoadFailure` with a detailed message showing every checked path and how to fix it.

## Async / isolate usage

**All `DatahikeClient` operations are synchronous and blocking.** In a Flutter app, a heavy query will freeze the UI thread.

### Worker isolate wrapper

Use `DatahikeIsolate` to run the native library inside a dedicated worker isolate:

```dart
final service = await DatahikeIsolate.start();
final result = await service.q('[:find ?e ...]', [DatahikeInput.database(config)]);
await service.close();
```

`DatahikeIsolate` exposes the same API as `DatahikeClient` but returns `Future<DatahikeResult<T>>`.

### Important restrictions

- **Never share a `DatahikeClient` across isolates.** It contains `DynamicLibrary` and `NativeCallable` references that are isolate-local.
- **`DatahikeIsolate` creates one persistent worker isolate** and keeps the native client alive inside it. This is efficient for repeated operations.
- **Heavy concurrent native calls may exhaust GraalVM stack space.** If you see `StackOverflowError` from the native layer, reduce concurrency or use a single `DatahikeIsolate` instance.

For one-off operations you can also use `Isolate.run` directly:

```dart
final result = await Isolate.run(() {
  final client = DatahikeClient.open();
  try {
    return client.q('[:find ?e ...]', [...]).getOrElse((_) => '');
  } finally {
    client.close();
  }
});
```

## Platform support

| Platform | Status | Verified version |
|----------|--------|------------------|
| Linux x64 | ✅ Tested | `libdatahike-0.8.1691-linux-amd64` |
| macOS arm64 | ✅ Tested | `libdatahike-0.8.1691-macos-aarch64` |
| macOS x64 | 🟡 Expected | Official release artifact available; not yet verified here |
| Windows x64 | 🟡 Expected | Official release artifact available; not yet verified here |
| Android | 🟡 Feasibility | See [mobile support notes](doc/mobile.md) |
| iOS | 🟡 Feasibility | See [mobile support notes](doc/mobile.md) |
| Web | ❌ Not supported | FFI approach incompatible with web |

## Testing

All tests (unit + integration) can be run with:

```bash
dart test
```

If you have not yet fetched the native library, unit tests still pass. Integration tests will fail with a clear error message pointing you to `dart tool/fetch_datahike_native.dart`.

## License

MIT.
