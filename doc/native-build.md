# Native Datahike library build notes

`datahike4dart` calls Datahike through Datahike's native C ABI. The Dart package does not build or bundle that native library yet.

## Required output

Build or obtain the native library for your platform:

- Linux: `libdatahike.so`
- macOS: `libdatahike.dylib`
- Windows: `datahike.dll`

## Build from upstream Datahike

Install prerequisites for Datahike's native-image build:

- GraalVM with `native-image`
- Babashka (`bb`)
- C/C++ build toolchain for your OS

Then:

```bash
git clone https://github.com/replikativ/datahike.git
cd datahike
bb ni-compile
```

The Datahike repository's native build currently generates the C entrypoints used by this package, including `create_database`, `transact`, `q`, `pull`, `schema`, and related functions.

## Load from Dart

Either set an environment variable:

```bash
export DATAHIKE_LIB=/absolute/path/to/libdatahike.so
dart run example/datahike4dart_example.dart
```

or pass a path explicitly:

```dart
final client = DatahikeClient.open(libraryPath: '/absolute/path/to/libdatahike.so');
```

## Test with a native library

The normal unit tests do not require Datahike native binaries:

```bash
dart test
```

Native integration tests are skipped unless `DATAHIKE_LIB` is set:

```bash
DATAHIKE_LIB=/absolute/path/to/libdatahike.so dart test test/native_integration_test.dart
```
