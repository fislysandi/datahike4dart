# Mobile support plan

Mobile is not part of the desktop MVP. This document tracks the feasibility investigation for Android and iOS support.

The Dart FFI layer is suitable for mobile. The main unknown is whether Datahike's native `libdatahike` can be cross-compiled and packaged reliably for each mobile platform.

## Android

Target proof:

1. Build an Android-compatible `libdatahike.so`, starting with `arm64-v8a`.
2. Package it in a Flutter plugin/example app under `android/src/main/jniLibs/arm64-v8a/`.
3. Load it from Dart FFI.
4. Run create/transact/query on an emulator or real device.

Open questions:

- Required GraalVM/native-image version and Android target support.
- Android NDK/toolchain configuration.
- Minimum Android API level.
- Native library size impact.
- Whether native calls need isolate/threading wrappers to avoid blocking UI code.

## iOS

Target proof:

1. Determine whether Datahike/GraalVM native-image can produce iOS-compatible static or dynamic libraries.
2. Package the result in a Flutter plugin/example app.
3. Handle signing/linking requirements.
4. Run create/transact/query on simulator or device.

Open questions:

- GraalVM iOS native-image support status for this library.
- Static vs dynamic linking feasibility.
- App Store compatibility and binary size.

## Web

Flutter Web / Dart Web is not supported by this FFI approach. Future web-friendly options would be separate work:

- a Datahike HTTP client, or
- a WASM-specific Datahike build if feasible.
