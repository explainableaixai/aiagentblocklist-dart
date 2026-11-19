// Used where dart:io exists: Flutter mobile and desktop, the Dart VM, servers.
import 'dart:io';
import 'dart:math';

/// Reads a variable from the process environment.
String? readEnvironment(String name) => Platform.environment[name];

/// Native platforms may set the User-Agent header.
const bool canSetUserAgent = true;

/// Whether file helpers are available.
const bool supportsFiles = true;

final Random _random = Random();

/// True when [path] is an existing regular file.
bool fileExists(String path) => File(path).existsSync();

/// Reads a whole text file.
String readText(String path) => File(path).readAsStringSync();

/// Joins a folder and a file name with the platform separator.
String joinPath(String dir, String name) {
  if (dir.endsWith('/') || dir.endsWith(Platform.pathSeparator)) {
    return '$dir$name';
  }
  return '$dir${Platform.pathSeparator}$name';
}

/// Creates [dir] and its parents when missing.
Future<void> ensureDir(String dir) => Directory(dir).create(recursive: true);

/// Writes [bytes] to a temp file next to [path], then renames it over [path].
Future<void> writeAtomic(String path, List<int> bytes) async {
  final target = File(path);
  await target.parent.create(recursive: true);
  final suffix = _random.nextInt(1 << 32).toRadixString(16);
  final tmp = File(joinPath(target.parent.path, '.aab-$pid-$suffix'));
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(path);
}
