# Contributing to datahike4dart

Thank you for considering a contribution! This document covers how to set up a development environment, run tests, and submit changes.

## Development setup

### Prerequisites

- Dart SDK 3.10+ (install via https://dart.dev/get-dart)
- Git
- For integration tests: a Datahike native library for your platform

### Clone and bootstrap

```bash
git clone https://github.com/fislysandi/datahike4dart.git
cd datahike4dart
dart pub get

# Fetch the native library for your platform
dart tool/fetch_datahike_native.dart
```

### Quick commands

We provide a `Makefile` for common tasks:

| Command | What it does |
|---------|--------------|
| `make deps` | Install Dart dependencies |
| `make format` | Run `dart format` on all source |
| `make analyze` | Run `dart analyze --fatal-infos` |
| `make test` | Run all tests except isolate (recommended) |
| `make test-all` | Run all tests including isolate |
| `make fetch-native` | Download the Datahike native library |
| `make ci` | Run the full CI check locally |
| `make publish-dry-run` | Validate the package for pub.dev |

Or run directly:

```bash
dart format --set-exit-if-changed lib test example tool example_flutter
dart analyze --fatal-infos
dart test --exclude-tags=isolate
dart pub publish --dry-run
```

## Testing

### Test structure

| File | What it tests |
|------|---------------|
| `test/datahike4dart_test.dart` | Unit tests for config/input parsing, error paths |
| `test/edn_parser_test.dart` | EDN parser correctness |
| `test/native_integration_test.dart` | Full end-to-end against native `libdatahike` |
| `test/tx_builder_test.dart` | Schema/transaction builders |
| `test/isolate_test.dart` | Async `DatahikeIsolate` wrapper |

### Running without the native library

Unit tests that don't need `libdatahike` can be filtered by excluding the integration tests. All non-integration tests are pure Dart and run anywhere:

```bash
dart test test/datahike4dart_test.dart test/edn_parser_test.dart test/tx_builder_test.dart
```

### The `isolate` tag

`DatahikeIsolate` tests spawn worker isolates that can cause GraalVM stack exhaustion under test-runner concurrency. They are tagged `@Tags(['isolate'])` and excluded from the default test run:

```bash
# Default: excludes isolate tests
dart test --exclude-tags=isolate

# Run only isolate tests
dart test --tags=isolate

# Run everything (may crash under high concurrency)
dart test
```

## Architecture

| File | Responsibility |
|------|---------------|
| `lib/src/native_library.dart` | Resolves and opens `libdatahike` for the host platform |
| `lib/src/datahike.dart` | Raw FFI bindings + `DatahikeClient` functional API |
| `lib/src/config.dart` | Immutable `DatahikeConfig` builders |
| `lib/src/tx.dart` | Schema attributes, `dbAdd`, `entityMap`, `ednValue`, etc. |
| `lib/src/edn.dart` | Lightweight recursive-descent EDN parser |
| `lib/src/isolate.dart` | `DatahikeIsolate` — async worker-isolate wrapper |
| `lib/src/cljd.dart` | Exception-based functional API for ClojureDart users |
| `lib/datahike4dart.dart` | Main Dart API entry point |
| `lib/cljd.dart` | ClojureDart API entry point |
| `tool/fetch_datahike_native.dart` | Downloads official release artifacts from GitHub |

## Code style

- `dart format` must pass (enforced in CI).
- `dart analyze --fatal-infos` must be clean.
- Prefer immutable data structures (`const`, `final`).
- Keep the public surface small; internals live in `lib/src/`.

## Submitting changes

1. Open an issue to discuss large changes.
2. Fork and create a feature branch.
3. Ensure tests pass and the package lints clean.
4. Open a PR with a clear description and test plan.

## Release checklist

Before publishing to pub.dev:

1. `make ci` passes locally.
2. `CHANGELOG.md` is updated.
3. Version in `pubspec.yaml` is bumped.
4. `git tag vX.Y.Z && git push origin vX.Y.Z`
5. `dart pub publish`

## Getting help

- Open an issue on GitHub
- Datahike upstream: https://github.com/replikativ/datahike
