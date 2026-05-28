import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Exception thrown when the native Datahike library cannot be located.
final class DatahikeLibraryException implements Exception {
  const DatahikeLibraryException(this.message);

  final String message;

  @override
  String toString() => 'DatahikeLibraryException: $message';
}

/// Resolves the native `libdatahike` library for the current platform.
///
/// Resolution order:
/// 1. Explicit [libraryPath].
/// 2. `DATAHIKE_LIB` environment variable.
/// 3. App-local conventional paths under the current working directory.
/// 4. Platform dynamic-loader default name.
final class DatahikeNativeLibrary {
  DatahikeNativeLibrary._();

  static String get _os => Platform.operatingSystem;

  static String? get _arch {
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final result = Process.runSync('uname', ['-m']);
        final stdout = result.stdout.toString().trim();
        if (result.exitCode == 0 && stdout.isNotEmpty) {
          return _normalizeArch(stdout);
        }
      } on Object {
        // ignore
      }
    }
    if (Platform.isWindows) {
      return _normalizeArch(Platform.environment['PROCESSOR_ARCHITECTURE']);
    }
    return null;
  }

  static String? _normalizeArch(String? arch) {
    return switch (arch) {
      'x86_64' || 'amd64' || 'AMD64' => 'amd64',
      'aarch64' || 'arm64' || 'ARM64' => 'aarch64',
      _ => arch,
    };
  }

  static String _libraryFileName() {
    if (Platform.isMacOS) return 'libdatahike.dylib';
    if (Platform.isWindows) return 'datahike.dll';
    return 'libdatahike.so';
  }

  static String? get _platformId {
    final arch = _arch;
    if (arch == null || arch == 'unknown') return null;
    return '$_os-$arch';
  }

  /// Returns every path that will be checked during resolution.
  static List<String> candidatePaths() {
    final libName = _libraryFileName();
    final cwd = Directory.current.path;
    final platformId = _platformId;

    final paths = <String>[];

    final env = Platform.environment['DATAHIKE_LIB'];
    if (env != null && env.isNotEmpty) {
      paths.add(env);
    }

    if (platformId != null) {
      paths.add(
        p.join(
          cwd,
          '.native',
          'libdatahike-$platformId',
          'libdatahike',
          'target',
          libName,
        ),
      );
    }
    // Some release archives extract directly to `.native/libdatahike/target/`.
    paths.add(p.join(cwd, '.native', 'libdatahike', 'target', libName));
    paths.add(p.join(cwd, '.native', libName));
    paths.add(libName);

    return paths;
  }

  /// Opens the native library using the resolution rules above.
  ///
  /// When [libraryPath] is provided, only that path is attempted.
  /// Otherwise the full search order is used.
  ///
  /// Throws [DatahikeLibraryException] when resolution fails.
  static DynamicLibrary open({String? libraryPath}) {
    if (libraryPath != null && libraryPath.isNotEmpty) {
      return _tryOpen(libraryPath, fallbackToSearch: false);
    }
    return _tryOpenAll();
  }

  static DynamicLibrary _tryOpen(
    String path, {
    required bool fallbackToSearch,
  }) {
    try {
      if (path == _libraryFileName()) {
        return DynamicLibrary.open(path);
      }
      if (File(path).existsSync()) {
        return DynamicLibrary.open(path);
      }
    } on Object catch (e) {
      throw DatahikeLibraryException(
        'Failed to open Datahike native library at: $path\n$e',
      );
    }

    if (!fallbackToSearch) {
      throw DatahikeLibraryException(
        'Datahike native library not found at: $path',
      );
    }

    return _tryOpenAll();
  }

  static DynamicLibrary _tryOpenAll() {
    final attempted = <String>[];
    final candidates = candidatePaths();

    for (final candidate in candidates) {
      attempted.add(candidate);
      try {
        if (candidate == _libraryFileName()) {
          return DynamicLibrary.open(candidate);
        }
        if (File(candidate).existsSync()) {
          return DynamicLibrary.open(candidate);
        }
      } on Object {
        // Candidate failed; try next.
      }
    }

    final platformId = _platformId ?? 'unknown';
    final buffer = StringBuffer()
      ..writeln('Could not find the Datahike native library.')
      ..writeln()
      ..writeln('Platform: $platformId')
      ..writeln('Expected file: ${_libraryFileName()}')
      ..writeln()
      ..writeln('Checked paths:')
      ..writeln(attempted.map((path) => '  - $path').join('\n'))
      ..writeln()
      ..writeln('To resolve:')
      ..writeln('  1. Set DATAHIKE_LIB to the absolute path to the library.')
      ..writeln('  2. Run: dart tool/fetch_datahike_native.dart')
      ..writeln('  3. Install libdatahike to a platform default search path.');

    throw DatahikeLibraryException(buffer.toString());
  }
}
