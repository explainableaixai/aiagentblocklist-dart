import 'dart:collection';
import 'dart:convert';

import 'entry.dart';
import 'exceptions.dart';
import 'platform_stub.dart' if (dart.library.io) 'platform_io.dart' as platform;

/// The parsed aab_full.json feed.
///
/// Lookup maps are built once in the constructor, so every check is a map
/// lookup (domains: one per label). Safe to share across isolates by
/// re-parsing, or to keep for the life of a server or app.
class Blocklist extends IterableBase<BlocklistEntry> {
  Blocklist._(this.product, this.version, this.counts, this.entries) {
    for (final e in entries) {
      _index(e);
    }
  }

  /// Builds a blocklist from a decoded aab_full.json document.
  factory Blocklist.fromMap(Map<String, dynamic> data) {
    final rows = data['entries'];
    if (rows is! List) {
      throw const AiAgentBlocklistException(
          'Not an AI Agent Blocklist document: "entries" is missing');
    }
    final counts = data['counts'];
    return Blocklist._(
      data['product']?.toString() ?? '',
      data['version']?.toString() ?? '',
      counts is Map<String, dynamic>
          ? Map<String, dynamic>.unmodifiable(counts)
          : const <String, dynamic>{},
      List<BlocklistEntry>.unmodifiable(
          rows.whereType<Map<String, dynamic>>().map(BlocklistEntry.fromJson)),
    );
  }

  /// Parses the text of aab_full.json.
  factory Blocklist.fromJson(String text) {
    final Object? data;
    try {
      data = jsonDecode(text);
    } on FormatException catch (e) {
      throw AiAgentBlocklistException(
          'aab_full.json is not valid JSON: ${e.message}');
    }
    if (data is! Map<String, dynamic>) {
      throw const AiAgentBlocklistException(
          'aab_full.json must be a JSON object');
    }
    return Blocklist.fromMap(data);
  }

  /// Reads a local aab_full.json (native platforms only).
  factory Blocklist.fromFile(String path) {
    final String text;
    try {
      text = platform.readText(path);
    } on UnsupportedError {
      rethrow;
    } catch (e) {
      throw AiAgentBlocklistException('Cannot read blocklist file $path: $e');
    }
    return Blocklist.fromJson(text);
  }

  /// Kinds matched by [checkExtension].
  static const Set<String> extensionKinds = {
    'chrome_ext',
    'edge_ext',
    'firefox_ext',
    'vscode_ext',
    'openvsx_ext',
    'jetbrains_plugin',
  };

  /// Kinds matched by [checkProcess].
  static const Set<String> processKinds = {
    'process_cli',
    'process_mac',
    'process_win',
  };

  /// Product name from the feed.
  final String product;

  /// Feed version string.
  final String version;

  /// The "counts" object as published.
  final Map<String, dynamic> counts;

  /// Every entry, in feed order.
  final List<BlocklistEntry> entries;

  final Map<String, BlocklistEntry> _byDomain = {};
  final Map<String, BlocklistEntry> _byExtension = {};
  final Map<String, BlocklistEntry> _byProcess = {};
  final Map<String, BlocklistEntry> _byNpm = {};
  final Map<String, BlocklistEntry> _byPypi = {};
  final Map<String, BlocklistEntry> _byIdent = {};

  @override
  Iterator<BlocklistEntry> get iterator => entries.iterator;

  @override
  int get length => entries.length;

  /// The entry for [hostOrUrl] or its nearest listed parent domain, or null.
  ///
  /// `api.example-agent.ai` matches a listed `example-agent.ai`;
  /// `notexample-agent.ai` does not.
  BlocklistEntry? checkDomain(String hostOrUrl) {
    var host = normalizeHost(hostOrUrl);
    while (host.isNotEmpty) {
      final hit = _byDomain[host];
      if (hit != null) return hit;
      final dot = host.indexOf('.');
      if (dot < 0) return null;
      host = host.substring(dot + 1);
    }
    return null;
  }

  /// Exact, case-insensitive match over browser extension and IDE plugin IDs.
  BlocklistEntry? checkExtension(String id) =>
      _byExtension[id.trim().toLowerCase()];

  /// Case-insensitive process or command name; `tool.exe` and `tool` match.
  BlocklistEntry? checkProcess(String name) => _byProcess[_processKey(name)];

  /// Package match for [ecosystem] `npm` or `pypi` (PEP 503 normalised).
  ///
  /// Throws [ArgumentError] for any other ecosystem.
  BlocklistEntry? checkPackage(String ecosystem, String name) {
    switch (ecosystem.trim().toLowerCase()) {
      case 'npm':
        return _byNpm[name.trim().toLowerCase()];
      case 'pypi':
        return _byPypi[normalizePypi(name)];
      default:
        throw ArgumentError.value(
            ecosystem, 'ecosystem', 'Use "npm" or "pypi"');
    }
  }

  /// Domain matching first, then an exact case-insensitive identifier match.
  BlocklistEntry? check(String identifier) =>
      checkDomain(identifier) ?? _byIdent[identifier.trim().toLowerCase()];

  /// Entries matching every given criterion (null means any). Ignores case.
  List<BlocklistEntry> filter(
      {String? agentType, String? kind, String? riskGrade}) {
    bool same(String value, String? wanted) =>
        wanted == null || value.toLowerCase() == wanted.toLowerCase();
    return entries
        .where((e) =>
            same(e.agentType, agentType) &&
            same(e.kind, kind) &&
            same(e.riskGrade, riskGrade))
        .toList();
  }

  /// Every listed domain, normalised and sorted.
  List<String> domains() => _byDomain.keys.toList()..sort();

  /// Distinct agent types, sorted.
  List<String> agentTypes() => _distinct((e) => e.agentType);

  /// Distinct kinds, sorted.
  List<String> kinds() => _distinct((e) => e.kind);

  /// Lowercase host from a URL or host: no scheme, user info, port, path,
  /// query, fragment or trailing dot.
  static String normalizeHost(String input) {
    var s = input.trim().toLowerCase();
    final scheme = RegExp(r'^[a-z][a-z0-9+.\-]*://').firstMatch(s);
    if (scheme != null) {
      s = s.substring(scheme.end);
    } else if (s.startsWith('//')) {
      s = s.substring(2);
    }
    final cut = s.indexOf(RegExp(r'[/?#\\]'));
    if (cut >= 0) s = s.substring(0, cut);
    final at = s.lastIndexOf('@');
    if (at >= 0) s = s.substring(at + 1);
    if (s.startsWith('[')) {
      final close = s.indexOf(']');
      s = close < 0 ? s.substring(1) : s.substring(1, close);
    } else {
      final colon = s.indexOf(':');
      if (colon >= 0) s = s.substring(0, colon);
    }
    while (s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// PEP 503: lowercase, runs of `-`, `_` and `.` become one `-`.
  static String normalizePypi(String name) =>
      name.trim().replaceAll(RegExp(r'[-_.]+'), '-').toLowerCase();

  static String _processKey(String name) {
    final key = name.trim().toLowerCase();
    return key.length > 4 && key.endsWith('.exe')
        ? key.substring(0, key.length - 4)
        : key;
  }

  List<String> _distinct(String Function(BlocklistEntry) field) =>
      entries.map(field).where((v) => v.isNotEmpty).toSet().toList()..sort();

  void _index(BlocklistEntry e) {
    final ident = e.ident.trim();
    if (ident.isEmpty) return;
    final lower = ident.toLowerCase();
    _byIdent.putIfAbsent(lower, () => e);
    if (e.kind == 'domain') {
      final host = normalizeHost(ident);
      if (host.isNotEmpty) _byDomain.putIfAbsent(host, () => e);
    } else if (extensionKinds.contains(e.kind)) {
      _byExtension.putIfAbsent(lower, () => e);
    } else if (processKinds.contains(e.kind)) {
      _byProcess.putIfAbsent(_processKey(ident), () => e);
    } else if (e.kind == 'npm') {
      _byNpm.putIfAbsent(lower, () => e);
    } else if (e.kind == 'pypi') {
      _byPypi.putIfAbsent(normalizePypi(ident), () => e);
    }
  }
}
