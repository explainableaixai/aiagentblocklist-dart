// Used where dart:io is missing (Flutter web, browsers). Downloads and
// in-memory checks work; the file helpers throw UnsupportedError.

/// No process environment on the web.
String? readEnvironment(String name) => null;

/// Browsers refuse to let scripts set the User-Agent header.
const bool canSetUserAgent = false;

/// Whether file helpers are available.
const bool supportsFiles = false;

Never _noFiles() => throw UnsupportedError(
    'File access is not available on this platform. Use download() and '
    'Blocklist.fromJson() instead.');

/// Not available without dart:io.
bool fileExists(String path) => _noFiles();

/// Not available without dart:io.
String readText(String path) => _noFiles();

/// Not available without dart:io.
String joinPath(String dir, String name) => _noFiles();

/// Not available without dart:io.
Future<void> ensureDir(String dir) async => _noFiles();

/// Not available without dart:io.
Future<void> writeAtomic(String path, List<int> bytes) async => _noFiles();
