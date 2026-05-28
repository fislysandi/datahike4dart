# datahike4dart Roadmap

This roadmap turns the verified MVP into a library we can comfortably use in real Dart and Flutter projects.

## Current state (last updated 2026-05-28)

### What works

- Dart package scaffold with `ffi`, `fpdart`, and `path`.
- Functional public API: `DatahikeClient` returns `Either<DatahikeFailure, T>`.
- Raw FFI layer: `Datahike.openRaw()`.
- **Native library resolver** (`DatahikeNativeLibrary`):
  - Searches explicit path → `DATAHIKE_LIB` → `.native/` conventional paths → platform default.
  - Detailed `DatahikeLoadFailure` messages with checked paths and fix instructions.
- **`tool/fetch_datahike_native.dart`** downloads official Datahike release artifacts from GitHub for the host platform into `.native/`.
- **Config builders**: `DatahikeConfig.file()`, `.memory()`, `.fromEdn()` with `SchemaFlexibility`, `keepHistory`, `initialTx`.
- Linux x64 native integration verified against Datahike `libdatahike-0.8.1691-linux-amd64`.
- **Typed result decoding**: `qRows()`, `pullMap()`, `entityMap()`, `datomsList()`, `Datom`.
- **EDN parser**: lightweight parser for Datahike output patterns.
- **Transaction/schema builders**: `SchemaAttribute`, `dbAdd`, `dbRetract`, `entityMap`, `ednValue`, `txData`, `schemaTx`.
- Integration tests: create, transact, query, pull, pullMany, entity, schema, reverseSchema, datoms, seekDatoms, branches, metrics, indexRange, commitId, parentCommitIds, branch, deleteBranch, JSON format.
- `dart format`, `dart analyze`, `dart test`, and `dart pub publish --dry-run` pass.

### Known critical issues

1. **Windows not yet verified.** Platform matrix covers Linux x64 and macOS arm64.
2. **Mobile feasibility blocked by library size.** `libdatahike` is ~145 MB uncompressed — a major concern for Android/iOS packaging.
3. **Heavy concurrent native calls can exhaust GraalVM stack space.** Mobile/desktop apps should use a single `DatahikeIsolate` instance. Isolate tests are tagged `isolate` and can be excluded with `dart test --exclude-tags=isolate`.

---

## Priority 0 — Keep the package healthy

These are always-on requirements before and after every change:

```bash
dart format --set-exit-if-changed lib test example tool
dart analyze
dart test
dart pub publish --dry-run
```

---

## Priority 1 — Native library distribution and loading

**STATUS: COMPLETED**

- ✅ `DatahikeNativeLibrary` resolver searches explicit `libraryPath` → `DATAHIKE_LIB` → `.native/` conventional paths → platform dynamic loader defaults.
- ✅ Clear `DatahikeLoadFailure` messages showing attempted paths and platform.
- ✅ `tool/fetch_datahike_native.dart` downloads official Datahike release artifacts for the host platform.
- ✅ Cache downloaded artifacts under `.native/` (git-ignored).
- ✅ README documents the install flow.

### Remaining

- [ ] Document checked platform/version matrix in README.
- [ ] Verify macOS amd64/aarch64 and update README.
- [ ] Verify Windows amd64 and update README if artifacts exist.

---

## Priority 2 — Config builders

**STATUS: COMPLETED**

- ✅ `DatahikeConfig` with `file()`, `memory()`, `fromEdn()` factories.
- ✅ `DatahikeStoreConfig` / `DatahikeFileStore` / `DatahikeMemoryStore`.
- ✅ `toEdn()` methods.
- ✅ `schemaFlexibility`, `keepHistory`, `initialTx`.
- ✅ Raw EDN escape hatch via `DatahikeConfig.fromEdn()`.
- ✅ Integration test uses config builders.

---

## Priority 3 — EDN helpers and typed result decoding

**STATUS: COMPLETED**

### Why this matters

EDN strings are acceptable for MVP, but production apps need safer helpers.

### Completed

- ✅ Implemented a lightweight Datahike-focused EDN parser in `lib/src/edn.dart`.
- ✅ `Datom` model with `fromRow()` factory.
- ✅ Typed helper methods on `DatahikeClient`:
  - `qRaw(...)` — alias for raw EDN `q`
  - `qRows(...)` — `Either<DatahikeFailure, List<List<Object?>>>`
  - `pullMap(...)` — `Either<DatahikeFailure, Map<Object?, Object?>?>`
  - `entityMap(...)` — `Either<DatahikeFailure, Map<Object?, Object?>?>`
  - `datomsList(...)` — `Either<DatahikeFailure, List<List<Object?>>>`
- ✅ Raw EDN methods remain available.

### Acceptance criteria

Basic query results and datoms can be consumed without manual string parsing.

---

## Priority 4 — Transaction and schema builders

**STATUS: COMPLETED**

Hand-writing transaction EDN is powerful but risky.

### Completed

- ✅ `SchemaAttribute` builder with `ident`, `valueType`, `cardinality`, `unique`, `index`, `fulltext`, `component`, `noHistory`.
- ✅ `ValueType`, `Cardinality`, `Uniqueness` enums.
- ✅ `dbAdd()` and `dbRetract()` helpers.
- ✅ `entityMap()` for map-form entity insert.
- ✅ `ednValue()` for safe Dart-to-EDN conversion.
- ✅ `txData()` and `schemaTx()` convenience wrappers.

### Acceptance criteria

The README quick start avoids manually writing schema EDN.

---

## Priority 5 — API completeness and correctness matrix

**STATUS: PARTIALLY COMPLETED**

### What's tested

- ✅ `createDatabase`, `deleteDatabase`, `databaseExists`
- ✅ `transact`
- ✅ `q`
- ✅ `pull`, `pullMany`
- ✅ `entity`
- ✅ `schema`, `reverseSchema`
- ✅ `datoms`, `seekDatoms`
- ✅ `branches`
- ✅ `metrics`
- ✅ `indexRange`
- ✅ `commitId`, `parentCommitIds`
- ✅ `branch`, `deleteBranch`
- ✅ JSON output format

### What's NOT tested against real native calls

- [ ] `mergeDb` (complex multi-parent merge; deferred until basic branching is stable)
- [ ] `gcStorage` (destructive operation; deferred to dedicated cleanup test suite)
- [ ] CBOR output format
- [ ] FFI signature drift detection against `libdatahike.h`

### Work items

- [x] Add native tests for every remaining public method.
- [x] Validate output formats: EDN and JSON first, CBOR later.
- [ ] Compare FFI signatures against generated `libdatahike.h` in tests or tooling.

### Acceptance criteria

Every public method has at least one native integration test or an explicit documented reason it is deferred.

---

## Priority 6 — Lifecycle, concurrency, and isolates

**STATUS: COMPLETED**

Current calls are synchronous. That is fine for CLI, but Flutter apps need guidance and likely async wrappers.

### Completed

- ✅ Fix `_CallbackCapture` to be per-instance using `NativeCallable.isolateLocal`.
- ✅ `DatahikeIsolate` worker service that runs `DatahikeClient` in a dedicated worker isolate and exposes an async API (`Future<DatahikeResult<T>>`).
- ✅ Documented sync/blocking behavior and isolate restrictions in README.
- ✅ Investigated isolate safety: `DatahikeClient` must not be shared across isolates; heavy concurrent native calls can exhaust GraalVM stack space.

### Acceptance criteria

A Flutter desktop app can run Datahike work without blocking the UI thread.

---

## Priority 7 — Desktop platform matrix

**STATUS: PARTIALLY COMPLETED**

Linux and macOS ARM64 are verified. Windows remains expected but unverified.

### Completed

- ✅ Added `.github/workflows/ci.yml` with Linux test matrix (stable + beta Dart SDK).
- ✅ Updated README with platform support table.
- ✅ Verified macOS arm64 (`libdatahike-0.8.1691-macos-aarch64`) on Apple Silicon M1.
  - All native integration tests pass: create, transact, query, pull, entity, schema, datoms, branches, metrics, indexRange, commitId, branch, JSON format.
  - `DatahikeIsolate` tests hit GraalVM stack exhaustion (same behavior as Linux under high concurrency).

### Remaining

- [ ] Verify Windows x64 with official release artifacts.
- [ ] Add Windows job to CI when verified.

### Acceptance criteria

Platform support claims distinguish tested, expected, and unsupported targets.

---

## Priority 8 — Flutter desktop example

**STATUS: COMPLETED**

A concrete app catches packaging/loading problems that CLI tests miss.

### Completed

- ✅ Added `example_flutter/` with a Material app demonstrating:
  - Start / Stop worker isolate buttons
  - Setup DB (create + schema + seed)
  - Query with typed results displayed in a list
  - All heavy work runs via `DatahikeIsolate`

### Acceptance criteria

A developer can run a Flutter desktop example and see queried Datahike data in the UI.

---

## Priority 9 — Mobile feasibility

**STATUS: COMPLETED**

Mobile comes after desktop stability.

### Completed

- ✅ Documented native library size concern (~145 MB uncompressed).
- ✅ Documented threading / stack exhaustion findings.
- ✅ Updated `doc/mobile.md` with concrete blockers and open questions.

### Remaining (deferred to future sprints)

- [ ] Android arm64 native library spike.
- [ ] Flutter plugin packaging spike.
- [ ] iOS native-image feasibility spike.

### Acceptance criteria

Either Android/iOS create/transact/query works, or the exact native-build blocker is documented.

---

## Recommended next sprint

Do these first, in order:

1. **Async / isolate wrappers (Priority 6)** — `TaskEither` wrappers, worker-isolate example, documented blocking behavior.
2. **Desktop platform matrix (Priority 7)** — verify macOS and Windows, update README platform table.
3. **Flutter desktop example (Priority 8)** — concrete app catching packaging/loading issues CLI tests miss.
4. **Mobile feasibility (Priority 9)** — Android arm64 native library spike, document blockers.

That sprint would move the package from "safe and ergonomic desktop CLI" to "ready for Flutter desktop and mobile exploration."
