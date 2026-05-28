# datahike4dart MVP Plan — Desktop First, Mobile Second

## Goal

Produce a usable MVP Dart package that makes Datahike available to Dart CLI/server and Flutter desktop through Datahike's native `libdatahike` C ABI, then use that proven package as the base for Android/iOS support.

## Non-goals for the MVP

- No Flutter Web support. `dart:ffi` does not target browser web.
- No pure Dart Datahike reimplementation.
- No polished typed EDN object model in the first MVP; EDN strings are acceptable.
- Functional API style is in scope: public operations should prefer `fpdart` result types over exception-driven control flow.
- No promise of Android/iOS until native Datahike library packaging is proven.

## Current repository baseline

- `pubspec.yaml` already declares a Dart package named `datahike4dart` with `ffi`, `path`, `lints`, and `test` dependencies; it should add `fpdart` for the public functional API.
- `lib/datahike4dart.dart` exports the package entrypoint.
- `lib/src/datahike.dart` contains an early FFI wrapper around Datahike native functions.
- `README.md` documents the native library requirement and an example.
- `example/datahike4dart_example.dart` and `test/datahike4dart_test.dart` exist.

## MVP acceptance criteria

### Package quality

- `dart pub get` succeeds.
- `dart format --set-exit-if-changed .` succeeds.
- `dart analyze` succeeds with zero issues.
- `dart test` succeeds without requiring a native Datahike library.
- Public API is documented enough for first users.
- Public MVP API exposes functional result values, e.g. `Either<DatahikeFailure, T>` / `TaskEither<DatahikeFailure, T>` where appropriate, rather than requiring users to catch exceptions.

### Desktop native behavior

Given a valid `libdatahike` path on Linux, and ideally macOS/Windows later:

- `Datahike.open(libraryPath: ...)` loads the library.
- `createDatabase(config)` succeeds.
- `databaseExists(config)` returns `true` after creation.
- `transact(config, schemaEdn)` installs a schema.
- `transact(config, txEdn)` writes data.
- `q(queryEdn, [DatahikeInput.database(config)])` returns expected EDN.
- `pull`, `entity`, `schema`, and `datoms` work on a fixture DB.
- Native `exception:` output becomes a typed `DatahikeFailure` in the functional API; the low-level/raw layer may still throw `DatahikeException` internally.
- `close()` can be called more than once safely.

### Deliverable shape

- A checked-in Dart package that can be used by another Dart CLI project via path dependency.
- A documented native library build/load workflow.
- A small integration example that proves create/transact/query.
- A clear `MOBILE.md` or README section explaining what is and is not supported yet.

## Architecture decision

Use Datahike's official/native C ABI through `dart:ffi`, with EDN strings as the first data representation and an `fpdart`-based functional public API.

### Why this path

- Fastest path to a real MVP.
- Avoids rewriting Datahike in Dart.
- Keeps Datahike semantics in the upstream engine.
- Matches Datahike's functional principles with immutable request/config objects and explicit success/failure values.
- Works naturally for Dart CLI/server and Flutter desktop.
- Leaves room for Android/iOS once native library builds are solved.

### Alternatives considered

1. Pure Dart port of Datahike
   - Rejected for MVP: much larger project, high semantic drift risk.
2. HTTP-only client
   - Good fallback for web/mobile, but not embedded/local Datahike.
3. JS/WASM bridge
   - Not suitable for native desktop MVP and uncertain for Datahike.

## Implementation plan

### Phase 0 — Freeze MVP scope

1. Treat desktop as the MVP target: Linux first, macOS/Windows best-effort.
2. Treat Android/iOS as separate packaging spikes after desktop works.
3. Keep the data representation EDN-first.
4. Make the public API functional-first with `fpdart`.
5. Defer typed query/result mapping until after MVP validation.

### Phase 1 — Repair and harden the current scaffold

Files:

- `lib/src/datahike.dart`
- `test/datahike4dart_test.dart`
- `README.md`

Tasks:

1. Ensure the current wrapper passes `dart analyze`.
2. Fix any incomplete cleanup from the interrupted scaffold work.
3. Confirm all native typedefs match Datahike's generated C entrypoint signatures.
4. Make callback capture safe for synchronous single-call usage.
5. Add guardrails:
   - closed-client check
   - missing-library error guidance
   - native exception conversion
6. Split layers clearly:
   - raw/private FFI layer: minimal, synchronous, may throw internal exceptions
   - public functional layer: returns `Either`/`TaskEither` with typed failures
7. Keep unit tests independent of `libdatahike`.

Verification:

```bash
dart format --set-exit-if-changed .
dart analyze
dart test
```

### Phase 2 — Native Datahike build workflow

Files:

- `tool/README.md` or `doc/native-build.md`
- optionally `tool/build_datahike_native.sh`

Tasks:

1. Document exact GraalVM/native-image prerequisites.
2. Document how to build Datahike's `libdatahike` from upstream.
3. Document how to expose it to Dart:
   - `DATAHIKE_LIB=/path/to/libdatahike.so`
   - or `Datahike.open(libraryPath: ...)`
4. Add a script only if it can remain simple and honest.

Verification:

- A fresh terminal can follow the docs and produce/load the native library.

### Phase 3 — Desktop integration tests

Files:

- `test/native_integration_test.dart`
- `example/datahike4dart_example.dart`

Tasks:

1. Add integration tests skipped unless `DATAHIKE_LIB` is set.
2. Use a temporary file-store path to avoid polluting user data.
3. Test the core MVP flow:
   - create DB
   - check exists
   - transact schema
   - transact entity
   - query entity
   - pull/entity/schema smoke tests
   - delete DB cleanup
4. Make failures print native error output clearly.

Verification:

```bash
dart test
DATAHIKE_LIB=/path/to/libdatahike.so dart test -P native
```

Or simpler:

```bash
DATAHIKE_LIB=/path/to/libdatahike.so dart test test/native_integration_test.dart
```

### Phase 4 — Functional API ergonomics pass

Files:

- `lib/src/datahike.dart`
- `README.md`
- `example/datahike4dart_example.dart`

Tasks:

1. Make method names Dart-like but preserve Datahike terms.
2. Add `fpdart` to dependencies and expose functional return types.
3. Model failures as a sealed hierarchy, for example:
   - `DatahikeLoadFailure`
   - `DatahikeNativeFailure`
   - `DatahikeClosedFailure`
   - `DatahikeInvalidInputFailure`
4. Prefer immutable value objects for config/input helpers.
5. Add convenience constructors for common configs:
   - file store config EDN builder
   - memory store config EDN builder, if native Datahike supports it reliably
6. Keep raw EDN escape hatches for advanced users.
7. Add simple helper docs for:
   - schema transaction
   - entity transaction
   - query
   - pull

Verification:

- Example app remains concise for the basic create/transact/query path.
- Example demonstrates functional error handling with `fold`, `match`, or equivalent `fpdart` style.

### Phase 5 — Desktop packaging matrix

Tasks:

1. Validate Linux x64 first.
2. Validate macOS Apple Silicon or Intel if available.
3. Validate Windows if available.
4. Record platform status in README:
   - tested
   - expected
   - unsupported
   - blocked

Verification:

- At least Linux native integration test passes before calling MVP done.
- macOS/Windows can be marked unverified if no machine/CI exists yet.

### Phase 6 — Mobile feasibility spike

Files/docs:

- `doc/mobile.md`
- possibly `flutter_example/` later

Android tasks:

1. Determine whether Datahike native-image can produce Android-compatible shared libraries.
2. Try `arm64-v8a` first.
3. Package `.so` in a Flutter plugin/example app.
4. Run create/transact/query on emulator or device.

IOS tasks:

1. Determine whether Datahike/GraalVM can produce iOS-compatible static/dynamic libraries.
2. Check App Store/runtime constraints.
3. Package into a Flutter plugin/example app if feasible.
4. Run create/transact/query on simulator/device.

Mobile acceptance criteria:

- Flutter Android app runs a local Datahike create/transact/query flow.
- Flutter iOS app does the same, or iOS is explicitly documented as blocked with the exact blocker.

## Risks and mitigations

### Risk: Datahike native library is difficult to build

Mitigation:

- Keep build docs precise.
- Do not block unit tests on native library availability.
- Consider prebuilt binaries after MVP.

### Risk: FFI signatures mismatch native entrypoints

Mitigation:

- Validate against Datahike generated `LibDatahike.java`/header.
- Add native integration tests for every wrapped function we claim to support.

### Risk: callback memory/lifetime issues

Mitigation:

- Start with synchronous calls only.
- Do not expose async/concurrent usage until proven.
- Document one-client/synchronous limitation if needed.

### Risk: Functional API feels heavy for simple scripts

Mitigation:

- Keep a small convenience layer for common flows.
- Consider exposing an explicitly named unsafe/raw API for advanced scripts, while documenting the functional API as the preferred stable interface.

### Risk: EDN strings are awkward for Dart users

Mitigation:

- Accept EDN for MVP.
- Add builders/helpers after correctness is proven.
- Consider an EDN parser/serializer or typed result layer in the polished library phase.

### Risk: mobile native-image is blocked

Mitigation:

- Treat mobile as a feasibility spike, not MVP commitment.
- If blocked, provide an HTTP Datahike client path for mobile/web apps that can talk to a server.

## Suggested timeline

### MVP desktop package

Estimated: 5–8 focused working days after native build environment is available, because the functional public API adds a small design/testing pass.

1. Scaffold cleanup and analyzer/tests: 0.5–1 day
2. Signature validation and wrapper hardening: 1–2 days
3. Functional `fpdart` public API layer: 1–1.5 days
4. Native build docs/script: 0.5–1 day
5. Native integration tests: 1–2 days
6. README/examples/API polish: 1 day

### Production daily-use package

Estimated: 2–3 additional weeks after MVP.

Includes:

- Better config builders
- result decoding helpers
- more complete integration tests
- CI matrix
- prebuilt binary strategy
- Flutter plugin packaging if needed
- versioning/release workflow

### Mobile support

Estimated: 3–8+ additional weeks depending on GraalVM/Datahike cross-compilation results.

## Done definition for MVP

The MVP is done when a user can clone this repo, point it at a built `libdatahike`, run a Dart example, and successfully create a local Datahike database, transact data, and query it from Dart on desktop.
