# Mobile support plan

Mobile is not part of the desktop MVP, but the intended path is Flutter + Dart FFI.

## Android

Target proof:

1. Build an Android-compatible Datahike shared library for `arm64-v8a`.
2. Package the `.so` in a Flutter plugin or example app.
3. Run create/transact/query on an emulator or device.

## iOS

Target proof:

1. Determine whether the Datahike/GraalVM native-image path can produce an iOS-compatible library.
2. Package it as a framework/static library if feasible.
3. Run create/transact/query on simulator or device.

## Web

Flutter Web / Dart Web is not supported by this FFI approach. A future web-friendly path would likely be a Datahike HTTP client or a separate WASM-specific design.
