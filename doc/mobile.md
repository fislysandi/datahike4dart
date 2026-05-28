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

---

## Android — BLOCKED

### What was tested

1. **Standard GraalVM native-image Android target** — Attempted `native-image --target=android-arm64`.
   - **Result**: `Error: Platform specified as android-arm64 isn't supported.`
   - Standard GraalVM native-image (tested with Oracle GraalVM 21.0.11) only supports desktop targets: `linux-amd64`, `linux-aarch64`, `darwin-amd64`, `darwin-aarch64`, `windows-amd64`.

2. **Gluon Substrate evaluation** — GluonHQ maintains a forked GraalVM + Substrate tool that CAN target Android.
   - **Result**: Feasible in theory, but requires significant upstream work in Datahike's build system.

### Why it's blocked

| Blocker | Detail |
|---------|--------|
| **1. No standard native-image Android support** | Oracle/GraalVM native-image does not recognize Android as a compilation target. Issue [#407](https://github.com/oracle/graal/issues/407) confirms cross-compilation is not supported. |
| **2. Android uses ART, not standard libc/JVM** | Android's runtime (ART), Bionic libc, and linker are incompatible with standard ELF shared libraries produced by `native-image --shared`. |
| **3. Gluon Substrate is the only known path** | GluonHQ has a modified GraalVM fork + Maven plugin (`gluonfx:sharedlib -Pandroid`) that produces Android-compatible binaries. However... |
| **4. Gluon path requires build system changes** | Datahike's current build (`bb ni-compile`) uses standard `native-image --shared`. The Gluon path requires: (a) Gluon's GraalVM fork, (b) their Maven/Gradle plugin, (c) Android SDK + NDK, (d) potentially JNI wrapper code around Datahike's C API entry points. |
| **5. Library size** | Even if compiled, ~145 MB per ABI is a hard constraint for mobile apps. |

### What would need to happen to unblock Android

1. **Upstream Datahike changes**:
   - Add a Gluon Substrate build target alongside the current `bb ni-compile`.
   - Modify `libdatahike/src/datahike/impl/LibDatahike.java` to support JNI entry points if Gluon requires them.
   - Potentially add Android-specific reflection/resource configuration for native-image.

2. **Build infrastructure**:
   - Download Gluon's GraalVM fork: https://github.com/gluonhq/graal/releases
   - Install Android SDK + NDK (user already has NDK 28.2 at `/opt/android-sdk/ndk/`).
   - Create a Maven/Gradle build config using the GluonFX plugin.
   - Run `mvn gluonfx:sharedlib -Pandroid` (or `staticlib`).

3. **Flutter plugin packaging**:
   - Create a Flutter plugin wrapping the compiled `.so`/`.a`.
   - Add per-ABI `android/src/main/jniLibs/` directories.
   - Wire Dart FFI to load the Android-specific library.

4. **Size optimization**:
   - Strip debug symbols.
   - Consider `libhike` feature-gating to reduce the compiled surface.

### Honest assessment

Android support is **not a configuration problem** — it's an **upstream build toolchain problem**. The Datahike project would need to add Gluon Substrate as a supported build target. Until that happens, `datahike4dart` cannot support Android regardless of how much wrapper code we write.

---

## iOS — BLOCKED

### What was tested

No builds attempted. iOS has the same fundamental constraint as Android: standard GraalVM native-image does not support iOS targets.

### Why it's blocked

| Blocker | Detail |
|---------|--------|
| **1. No standard native-image iOS support** | Same as Android — iOS is not a supported `--target` for standard native-image. |
| **2. iOS requires signed static libraries** | iOS apps must use static libraries or frameworks that are signed. The standard `native-image --shared` produces dynamic `.dylib` / `.so` files, which are not suitable for iOS App Store distribution. |
| **3. Gluon Substrate is the only known path** | Gluon Substrate supports iOS via `mvn gluonfx:staticlib -Pios`. Same caveats as Android: requires Gluon's GraalVM fork, their build plugin, and potentially JNI wrapper code. |
| **4. App Store binary size limits** | iOS apps over 200 MB trigger App Store scrutiny. A 145 MB static library would dominate the binary. |

### What would need to happen to unblock iOS

Same upstream work as Android, plus:
- Static library output instead of shared library.
- Xcode framework packaging.
- iOS simulator + device architecture fat binary (`arm64` + `x86_64` simulator).
- Code signing integration.

---

## Web — NOT SUPPORTED

Flutter Web / Dart Web is not supported by this FFI approach. Future web-friendly options would be separate work:

- a Datahike HTTP client, or
- a WASM-specific Datahike build if feasible.

---

## Summary

| Platform | Status | Blocker |
|----------|--------|---------|
| Linux x64 | ✅ Working | None |
| macOS arm64/x64 | ✅ Working | None |
| Windows x64 | 🟡 Expected | Needs testing |
| Android | ❌ Blocked | Upstream: GraalVM native-image does not support Android |
| iOS | ❌ Blocked | Upstream: GraalVM native-image does not support iOS |
| Web | ❌ Not applicable | FFI incompatible with web platform |

**Recommendation**: If mobile support is a hard requirement, the most productive path is to open an issue on the [Datahike repository](https://github.com/replikativ/datahike) requesting Gluon Substrate / mobile build targets. Once Datahike produces official Android/iOS artifacts, `datahike4dart` can add the Flutter plugin packaging and FFI loading logic in a matter of hours.
