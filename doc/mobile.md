# Mobile support plan

Mobile is not part of the desktop MVP. This document tracks the feasibility investigation for Android and iOS support.

The Dart FFI layer is suitable for mobile. The main unknown is whether Datahike's native `libdatahike` can be cross-compiled and packaged reliably for each mobile platform.

## Current findings (2026-05-28)

### Native library size

The official Linux amd64 `libdatahike.so` is **~145 MB uncompressed**. For mobile, this is a significant size concern:

- Android APK/AAB size budget is typically ~50-150 MB total.
- iOS apps over ~200 MB face App Store scrutiny.
- The library would need to be stripped or split-per-ABI to reduce impact.

### Threading model

GraalVM native images use OS threads for isolates. In testing, running multiple Datahike clients concurrently from different Dart isolates has caused **native stack exhaustion** (`StackOverflowError` from the GraalVM layer). This suggests:

- Mobile apps should use a **single shared worker isolate** (via `DatahikeIsolate`) for all Datahike work.
- Avoid creating multiple `DatahikeClient` instances on mobile.

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
- Native library size impact (~145 MB per ABI).
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
