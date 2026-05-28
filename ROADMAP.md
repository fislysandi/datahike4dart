# datahike4dart Roadmap

This roadmap turns the verified MVP into a library we can comfortably use in real Dart and Flutter projects.

## Current baseline

Already working:

- Dart package scaffold with `ffi` and `fpdart`.
- Functional public API: `DatahikeClient` returns `Either<DatahikeFailure, T>`.
- Raw FFI layer: `Datahike.openRaw()`.
- Linux x64 native integration verified against Datahike `libdatahike-0.8.1689-linux-amd64`.
- Core flow verified: open native library, create DB, transact schema, transact entity, query, cleanup.
- `dart analyze`, `dart test`, and `dart pub publish --dry-run` pass.

## Product target

A daily-use embedded Datahike library for Dart/Flutter projects with:

1. predictable native library installation/loading,
2. ergonomic functional API,
3. safe config and EDN builders,
4. decoded/typed result options,
5. broad integration test coverage,
6. documented desktop support,
7. a clear path to Flutter desktop and later Android/iOS.

## Priority 0 — Keep the package healthy

These are always-on requirements before and after every change:

```bash
dart format --set-exit-if-changed lib test example
dart analyze
dart test
DATAHIKE_LIB=/absolute/path/to/libdatahike.so dart test test/native_integration_test.dart
dart pub publish --dry-run
```

## Priority 1 — Native library distribution and loading

This is the biggest adoption blocker. The Dart API is only useful if projects can reliably get `libdatahike`.

### Work items

- Add a `DatahikeNativeLibrary` resolver that searches, in order:
  1. explicit `libraryPath`,
  2. `DATAHIKE_LIB`,
  3. app-local conventional paths,
  4. platform dynamic loader defaults.
- Add clear `DatahikeLoadFailure` messages showing attempted paths and platform.
- Add a `tool/fetch_datahike_native.dart` script to download official Datahike release artifacts for the host platform.
- Cache downloaded artifacts under a local ignored directory.
- Document checked platform/version matrix.

### Acceptance criteria

- A fresh Linux x64 checkout can run one command to download `libdatahike` and then pass native integration tests.
- Missing-library failures tell the user exactly what to install or set.

## Priority 2 — Config builders

Raw EDN config strings are too error-prone for daily use.

### Work items

- Add immutable config value objects:
  - `DatahikeConfig`
  - `DatahikeStoreConfig`
  - `DatahikeFileStore`
  - `DatahikeMemoryStore` if verified
- Add `toEdn()` methods.
- Support common options:
  - `schemaFlexibility`
  - `keepHistory`
  - initial transaction EDN
  - branch/id fields where appropriate
- Preserve raw EDN escape hatch.

### Acceptance criteria

Users can write:

```dart
final config = DatahikeConfig.file(
  path: '/tmp/app-db',
  id: 'f11e0000-0000-0000-0000-000000000001',
  schemaFlexibility: SchemaFlexibility.write,
).toEdn();
```

and the generated config passes native create/transact/query tests.

## Priority 3 — EDN helpers and typed result decoding

EDN strings are acceptable for MVP, but production apps need safer helpers.

### Work items

- Decide whether to depend on an EDN parser package or implement a small Datahike-focused parser.
- Add minimal typed models:
  - `Datom`
  - query row helpers
  - pull/entity map helpers
- Add helper methods that return decoded data alongside raw methods:
  - `qRaw(...) -> Either<DatahikeFailure, String>`
  - `qRows(...) -> Either<DatahikeFailure, List<List<Object?>>>`
  - similar for `pull`, `entity`, `datoms`.
- Keep raw EDN methods available because Datahike values can be richer than Dart's primitive model.

### Acceptance criteria

Basic query results and datoms can be consumed without manual string parsing.

## Priority 4 — Transaction and schema builders

Hand-writing transaction EDN is powerful but risky.

### Work items

- Add schema attribute builder:
  - ident
  - value type
  - cardinality
  - uniqueness/index flags
- Add transaction builders:
  - map-form entity insert
  - `db/add`
  - `db/retract`
- Add EDN escaping for strings/keywords/UUIDs.

### Acceptance criteria

The README quick start can avoid manually writing schema EDN except in advanced examples.

## Priority 5 — API completeness and correctness matrix

The MVP wraps many native functions, but the integration test only proves the core flow.

### Work items

- Add native tests for every public method:
  - `pull`, `pullMany`, `entity`
  - `schema`, `reverseSchema`, `metrics`
  - `datoms`, `seekDatoms`, `indexRange`
  - `commitId`, `parentCommitIds`
  - `branches`, `branch`, `deleteBranch`, `mergeDb`
  - `gcStorage`
- Validate output formats: EDN and JSON first, CBOR later.
- Compare FFI signatures against generated `libdatahike.h` in tests or tooling.

### Acceptance criteria

Every public method has at least one native integration test or an explicit documented reason it is deferred.

## Priority 6 — Lifecycle, concurrency, and isolates

Current calls are synchronous. That is fine for CLI, but Flutter apps need guidance and likely async wrappers.

### Work items

- Document sync/blocking behavior.
- Add `TaskEither` wrappers for app code.
- Investigate whether calls are safe across Dart isolates.
- Add a simple worker-isolate example for Flutter/desktop apps.
- Make `close()` and final cleanup semantics explicit.

### Acceptance criteria

A Flutter desktop app can run Datahike work without blocking the UI thread.

## Priority 7 — Desktop platform matrix

Linux is verified. Daily-use confidence needs macOS and Windows.

### Work items

- Verify macOS arm64/x64 with official release artifacts.
- Verify Windows x64 with official release artifacts if available.
- Add CI jobs where practical.
- Update README platform table with tested versions.

### Acceptance criteria

Platform support claims distinguish tested, expected, and unsupported targets.

## Priority 8 — Flutter desktop example

A concrete app catches packaging/loading problems that CLI tests miss.

### Work items

- Add `example_flutter/` or a separate small example app.
- Demonstrate native library loading.
- Demonstrate create/transact/query from a UI action.
- Keep heavy work off the UI thread if possible.

### Acceptance criteria

A developer can run a Flutter desktop example and see queried Datahike data in the UI.

## Priority 9 — Mobile feasibility

Mobile comes after desktop stability.

### Work items

- Android arm64 native library spike.
- Flutter plugin packaging spike.
- iOS native-image feasibility spike.
- Document blockers and alternatives.

### Acceptance criteria

Either Android/iOS create/transact/query works, or the exact native-build blocker is documented.

## Recommended next sprint

Do these first, in order:

1. **Native artifact fetcher/resolver** — removes the biggest friction from using the package.
2. **Config builders** — removes unsafe hand-written config strings.
3. **Expand native integration tests to `pull`, `entity`, `schema`, `datoms`** — proves the API beyond query.
4. **README refresh around the new install flow** — makes the library usable by other projects.

That sprint would move the package from “verified MVP” to “usable in our own desktop Dart projects without hand setup.”
