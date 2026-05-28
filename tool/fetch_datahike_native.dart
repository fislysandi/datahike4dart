#!/usr/bin/env dart
// Fetches the official Datahike native library release artifact for the host
// platform and extracts it under `.native/`.
//
// Usage:
//   dart tool/fetch_datahike_native.dart
//   dart tool/fetch_datahike_native.dart --version=0.8.1691
//   dart tool/fetch_datahike_native.dart --output-dir=.native

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const _repoOwner = 'replikativ';
const _repoName = 'datahike';

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);

  if (opts.help) {
    _printUsage();
    return;
  }

  final platform = opts.platform ?? _detectPlatform();
  final arch = opts.arch ?? _detectArch();

  if (platform == null || arch == null) {
    stderr.writeln('Could not auto-detect platform/architecture.');
    stderr.writeln('Use --platform and --arch to specify them manually.');
    exit(1);
  }

  final assetName = 'libdatahike-${opts.version}-$platform-$arch.zip';
  final outputDir = p.absolute(opts.outputDir);

  stdout.writeln('Datahike native fetcher');
  stdout.writeln('  version : ${opts.version}');
  stdout.writeln('  platform: $platform');
  stdout.writeln('  arch    : $arch');
  stdout.writeln('  asset   : $assetName');
  stdout.writeln('  output  : $outputDir');
  stdout.writeln();

  final release = await _fetchRelease(opts.version, token: opts.token);
  final asset = release.assets.firstWhere(
    (a) => a['name'] == assetName,
    orElse: () => <String, Object?>{},
  );

  if (asset.isEmpty) {
    stderr.writeln('Asset not found: $assetName');
    stderr.writeln('Available assets:');
    for (final a in release.assets) {
      final name = a['name'] as String? ?? 'unknown';
      if (name.endsWith('.zip')) {
        stderr.writeln('  - $name');
      }
    }
    exit(1);
  }

  final downloadUrl = asset['browser_download_url'] as String;
  final zipPath = p.join(outputDir, assetName);

  await _download(downloadUrl, zipPath, token: opts.token);
  _extract(zipPath, outputDir);
  File(zipPath).deleteSync();

  final extractedDir = p.join(outputDir, 'libdatahike-$platform-$arch');
  final libPath = p.join(
    extractedDir,
    'libdatahike',
    'target',
    _libraryFileName(platform),
  );

  stdout.writeln('Done. Library extracted to:');
  stdout.writeln('  $libPath');
  stdout.writeln();
  stdout.writeln('You can now run native integration tests with:');
  stdout.writeln('  dart test');
}

void _printUsage() {
  stdout.writeln('''
Fetch the official Datahike native library release artifact.

Usage: dart tool/fetch_datahike_native.dart [options]

Options:
  --version=<tag>     Release tag to fetch (default: latest)
  --output-dir=<dir>  Directory to extract into (default: .native)
  --platform=<os>     Override platform detection (linux, macos)
  --arch=<arch>       Override architecture detection (amd64, aarch64)
  --token=<token>     GitHub personal access token (optional, for rate limits)
  --help              Show this help message
''');
}

_Options _parseArgs(List<String> args) {
  String? version;
  String? outputDir;
  String? platform;
  String? arch;
  String? token;
  var help = false;

  for (final arg in args) {
    if (arg == '--help') {
      help = true;
    } else if (arg.startsWith('--version=')) {
      version = arg.substring('--version='.length);
    } else if (arg.startsWith('--output-dir=')) {
      outputDir = arg.substring('--output-dir='.length);
    } else if (arg.startsWith('--platform=')) {
      platform = arg.substring('--platform='.length);
    } else if (arg.startsWith('--arch=')) {
      arch = arg.substring('--arch='.length);
    } else if (arg.startsWith('--token=')) {
      token = arg.substring('--token='.length);
    } else {
      stderr.writeln('Unknown argument: $arg');
      exit(1);
    }
  }

  return _Options(
    version: version ?? 'latest',
    outputDir: outputDir ?? '.native',
    platform: platform,
    arch: arch,
    token: token,
    help: help,
  );
}

String? _detectPlatform() {
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  return null;
}

String? _detectArch() {
  if (Platform.isLinux || Platform.isMacOS) {
    try {
      final result = Process.runSync('uname', ['-m']);
      final out = result.stdout.toString().trim();
      if (result.exitCode == 0) return _normalizeArch(out);
    } on Object {
      // ignore
    }
  }
  if (Platform.isWindows) {
    return _normalizeArch(Platform.environment['PROCESSOR_ARCHITECTURE']);
  }
  return null;
}

String? _normalizeArch(String? arch) {
  return switch (arch) {
    'x86_64' || 'amd64' || 'AMD64' => 'amd64',
    'aarch64' || 'arm64' || 'ARM64' => 'aarch64',
    _ => arch,
  };
}

String _libraryFileName(String platform) {
  if (platform == 'macos') return 'libdatahike.dylib';
  if (platform == 'windows') return 'datahike.dll';
  return 'libdatahike.so';
}

Future<_Release> _fetchRelease(String version, {String? token}) async {
  final url = version == 'latest'
      ? 'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest'
      : 'https://api.github.com/repos/$_repoOwner/$_repoName/releases/tags/$version';

  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    if (token != null && token.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception(
        'GitHub API returned ${response.statusCode}: '
        '${body.substring(0, body.length.clamp(0, 200))}',
      );
    }

    final data = jsonDecode(body) as Map<String, Object?>;
    final tag = data['tag_name'] as String;
    final assets = (data['assets'] as List<Object?>?) ?? <Object?>[];
    return _Release(tag: tag, assets: assets.cast<Map<String, Object?>>());
  } finally {
    client.close();
  }
}

Future<void> _download(String url, String dest, {String? token}) async {
  stdout.writeln('Downloading $url ...');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    if (token != null && token.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    final response = await request.close();

    if (response.statusCode != 200) {
      throw Exception('Download failed with HTTP ${response.statusCode}');
    }

    Directory(p.dirname(dest)).createSync(recursive: true);
    final file = File(dest).openSync(mode: FileMode.writeOnly);
    try {
      await for (final chunk in response) {
        file.writeFromSync(chunk);
      }
    } finally {
      file.closeSync();
    }
  } finally {
    client.close();
  }
}

void _extract(String zipPath, String outputDir) {
  stdout.writeln('Extracting to $outputDir ...');
  Directory(outputDir).createSync(recursive: true);
  final result = Process.runSync('unzip', [
    '-o',
    '-q',
    zipPath,
    '-d',
    outputDir,
  ]);
  if (result.exitCode != 0) {
    throw Exception('unzip failed: ${result.stderr}');
  }
}

final class _Options {
  const _Options({
    required this.version,
    required this.outputDir,
    this.platform,
    this.arch,
    this.token,
    required this.help,
  });

  final String version;
  final String outputDir;
  final String? platform;
  final String? arch;
  final String? token;
  final bool help;
}

final class _Release {
  const _Release({required this.tag, required this.assets});

  final String tag;
  final List<Map<String, Object?>> assets;
}
