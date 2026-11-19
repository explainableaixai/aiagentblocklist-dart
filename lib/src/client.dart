import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'blocklist.dart';
import 'exceptions.dart';
import 'platform_stub.dart' if (dart.library.io) 'platform_io.dart' as platform;

/// Feed client for the AI Agent Blocklist.
///
/// There is no lookup API: the client fetches the files behind your private
/// download link, keeps local copies current with conditional requests and
/// parses aab_full.json so checks run inside your app or server.
class AiAgentBlocklistClient {
  /// Creates a client.
  ///
  /// The token comes from [token], then the `AIAGENTBLOCKLIST_TOKEN`
  /// environment variable (native platforms), then a compile-time
  /// `--dart-define=AIAGENTBLOCKLIST_TOKEN=...`. It must be 32 letters and
  /// digits; a [TokenException] is thrown before any request otherwise.
  AiAgentBlocklistClient({
    String? token,
    String baseUrl = defaultBaseUrl,
    this.timeout = const Duration(seconds: 30),
    this.userAgent = defaultUserAgent,
    http.Client? httpClient,
  })  : _token = _resolveToken(token),
        baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  /// Package version.
  static const String version = '1.0.0';

  /// Default site.
  static const String defaultBaseUrl = 'https://www.aiagentblocklist.com';

  /// Environment variable read when no token is passed.
  static const String tokenEnv = 'AIAGENTBLOCKLIST_TOKEN';

  /// Default User-Agent header (native platforms only).
  static const String defaultUserAgent =
      'aiagentblocklist-dart/$version (+https://www.aiagentblocklist.com)';

  /// Every file published behind a download link.
  static const List<String> files = [
    'aab_full.csv',
    'aab_full.json',
    'domains.txt',
    'firewall_edl.txt',
    'hosts.txt',
    'proxy.pac',
    'dns_rpz.zone',
    'chrome_extension_blocklist.json',
    'edge_extension_blocklist.json',
    'chrome_edge_extension_blocklist.reg',
    'chrome_edge_extensions.mobileconfig',
    'firefox_extension_ids.txt',
    'macos_bundle_ids.txt',
    'windows_package_ids.txt',
    'process_names.txt',
    'npm_packages.txt',
    'pypi_packages.txt',
    'counts.json',
    'README.txt',
  ];

  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9]{32}$');
  static final RegExp _filePattern = RegExp(
      r'^[A-Za-z0-9][A-Za-z0-9_]*\.(csv|json|txt|pac|zone|reg|mobileconfig)$');

  final String _token;

  /// Site root without a trailing slash.
  final String baseUrl;

  /// Timeout for each request.
  final Duration timeout;

  /// User-Agent sent on native platforms.
  final String userAgent;

  final http.Client _http;
  final bool _ownsHttp;

  static String _resolveToken(String? explicit) {
    var token = explicit?.trim() ?? '';
    if (token.isEmpty) token = platform.readEnvironment(tokenEnv)?.trim() ?? '';
    if (token.isEmpty) token = const String.fromEnvironment(tokenEnv).trim();
    if (token.isEmpty) {
      throw const TokenException(
          'No token: pass one or set AIAGENTBLOCKLIST_TOKEN');
    }
    if (!_tokenPattern.hasMatch(token)) {
      throw const TokenException(
          'The token must be exactly 32 letters and digits, as in your download link');
    }
    return token;
  }

  /// Checks a feed file name and returns it.
  ///
  /// Throws [AiAgentBlocklistException] for names outside the published pattern.
  static String checkFileName(String name) {
    if (!_filePattern.hasMatch(name)) {
      throw AiAgentBlocklistException(
          'Invalid file name "$name": expected a name like domains.txt or aab_full.json');
    }
    return name;
  }

  /// The comparable core of an ETag: no `W/`, no quotes, no `-gzip` suffix.
  static String bareEtag(String etag) {
    var e = etag.trim();
    if (e.startsWith('W/') || e.startsWith('w/')) e = e.substring(2);
    if (e.startsWith('"')) e = e.substring(1);
    if (e.endsWith('"')) e = e.substring(0, e.length - 1);
    if (e.endsWith('-gzip')) e = e.substring(0, e.length - 5);
    return e;
  }

  /// URL of the HTML page that lists your files.
  Uri get fileListUrl => Uri.parse('$baseUrl/download/$_token/');

  /// Full URL of one file.
  Uri fileUrl(String name) =>
      Uri.parse('$baseUrl/download/$_token/${checkFileName(name)}');

  /// Downloads one file and returns its bytes.
  Future<Uint8List> download(String name) async =>
      (await _get(name, const {})).bodyBytes;

  /// Downloads one file and decodes it as UTF-8.
  Future<String> downloadText(String name) async =>
      utf8.decode(await download(name), allowMalformed: true);

  /// Conditional download into [path] (native platforms).
  ///
  /// The ETag is kept in `<path>.etag` and sent as If-None-Match next time.
  /// Returns false when nothing changed (304, or the same bare ETag on a
  /// 200) and true after an atomic write (temp file, then rename).
  Future<bool> downloadTo(String name, String path) async {
    checkFileName(name);
    final sidecar = '$path.etag';
    var stored = '';
    if (platform.fileExists(path) && platform.fileExists(sidecar)) {
      stored = platform.readText(sidecar).trim();
    }
    final res =
        await _get(name, stored.isEmpty ? const {} : {'If-None-Match': stored});
    if (res.statusCode == 304) return false;

    final etag = (res.headers['etag'] ?? '').trim();
    if (stored.isNotEmpty &&
        etag.isNotEmpty &&
        bareEtag(etag) == bareEtag(stored)) {
      return false;
    }
    try {
      await platform.writeAtomic(path, res.bodyBytes);
      await platform.writeAtomic(sidecar, utf8.encode(etag));
    } on UnsupportedError {
      rethrow;
    } catch (e) {
      throw AiAgentBlocklistException('Cannot write $path: $e');
    }
    return true;
  }

  /// Fetches each name into [dir] and returns `{name: updated}`.
  ///
  /// All names are checked before the first request.
  Future<Map<String, bool>> sync(String dir, {Iterable<String>? names}) async {
    final list = List<String>.of(names ?? files);
    list.forEach(checkFileName);
    await platform.ensureDir(dir);
    final out = <String, bool>{};
    for (final name in list) {
      out[name] = await downloadTo(name, platform.joinPath(dir, name));
    }
    return out;
  }

  /// Downloads aab_full.json and parses it.
  Future<Blocklist> loadBlocklist() async =>
      Blocklist.fromJson(await downloadText('aab_full.json'));

  /// Closes the HTTP client if this instance created it.
  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<http.Response> _get(String name, Map<String, String> extra) async {
    final uri = fileUrl(name);
    final headers = <String, String>{
      'Accept': '*/*',
      if (platform.canSetUserAgent) 'User-Agent': userAgent,
      ...extra,
    };
    final http.Response res;
    try {
      res = await _http.get(uri, headers: headers).timeout(timeout);
    } on TimeoutException {
      throw AiAgentBlocklistException(
          'Network error while fetching $name: timed out after $timeout');
    } on AiAgentBlocklistException {
      rethrow;
    } catch (e) {
      throw AiAgentBlocklistException('Network error while fetching $name: $e');
    }

    final status = res.statusCode;
    if ((status >= 200 && status < 300) || status == 304) return res;
    if (status == 404) {
      throw NotFoundException(
          'Not found (404) for $name: the token or the file name is unknown');
    }
    if (status == 403) {
      throw const AccessEndedException(
          'Access ended (403): the subscription for this token has ended or is paused');
    }
    throw HttpStatusException('Unexpected HTTP $status while fetching $name',
        status: status);
  }

  @override
  String toString() => 'AiAgentBlocklistClient($baseUrl, token: [hidden])';
}
