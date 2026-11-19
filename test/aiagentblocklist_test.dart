import 'dart:io';

import 'package:aiagentblocklist/aiagentblocklist.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const token = 'abcdEFGH1234abcdEFGH1234abcdEFGH';
final String fixture = File('test/fixtures/aab_full.json').readAsStringSync();

AiAgentBlocklistClient clientWith(MockClientHandler handler) =>
    AiAgentBlocklistClient(token: token, httpClient: MockClient(handler));

Directory tempDir() => Directory.systemTemp.createTempSync('aab-dart-test-');

void main() {
  final list = Blocklist.fromJson(fixture);

  group('token and file names', () {
    test('explicit token builds file URLs', () {
      final c = AiAgentBlocklistClient(
          token: token, baseUrl: 'http://127.0.0.1:9000/');
      expect(
          c.fileListUrl.toString(), 'http://127.0.0.1:9000/download/$token/');
      expect(c.fileUrl('proxy.pac').toString(),
          'http://127.0.0.1:9000/download/$token/proxy.pac');
      expect(c.toString(), isNot(contains(token)));
      expect(AiAgentBlocklistClient.checkFileName('README.txt'), 'README.txt');
    });

    test('bad tokens throw TokenException before any request', () {
      for (final bad in [
        'abc123',
        '${token}x',
        'abcdEFGH1234abcdEFGH1234abcdEF-!',
        '$token\nX',
      ]) {
        expect(
            () => AiAgentBlocklistClient(
                token: bad,
                httpClient: MockClient((_) => fail('no request expected'))),
            throwsA(isA<TokenException>()
                .having((e) => e.status, 'status', isNull)),
            reason: bad);
      }
    });

    test('missing token is reported', () {
      if ((Platform.environment[AiAgentBlocklistClient.tokenEnv] ?? '')
          .isNotEmpty) {
        return;
      }
      expect(() => AiAgentBlocklistClient(), throwsA(isA<TokenException>()));
    });

    test('bad file names are rejected without a request', () async {
      final c = clientWith((_) => fail('no request expected'));
      for (final bad in [
        '../etc/passwd',
        'a/b.txt',
        '_x.txt',
        'my-file.txt',
        'domains.exe',
        'domains',
        'domains.txt?x',
        'domains.txt\n',
      ]) {
        await expectLater(
            c.download(bad), throwsA(isA<AiAgentBlocklistException>()),
            reason: bad);
      }
    });
  });

  group('HTTP', () {
    test('download sends the user agent', () async {
      late http.Request seen;
      final c = clientWith((req) async {
        seen = req;
        return http.Response('example-agent.ai\n', 200,
            headers: {'etag': '"v1"'});
      });
      expect(await c.downloadText('domains.txt'), 'example-agent.ai\n');
      expect(seen.method, 'GET');
      expect(seen.url.path, '/download/$token/domains.txt');
      expect(seen.headers['User-Agent'],
          'aiagentblocklist-dart/1.0.0 (+https://www.aiagentblocklist.com)');
    });

    test('status codes map to exceptions', () async {
      final cases = {
        404: isA<NotFoundException>(),
        403: isA<AccessEndedException>(),
        500: isA<HttpStatusException>(),
        429: isA<HttpStatusException>(),
      };
      for (final entry in cases.entries) {
        final c = clientWith((_) async => http.Response('nope', entry.key));
        await expectLater(
            c.download('hosts.txt'),
            throwsA(allOf(
                entry.value,
                isA<AiAgentBlocklistException>()
                    .having((e) => e.status, 'status', entry.key)
                    .having(
                        (e) => e.message, 'message', isNot(contains(token))))));
      }
    });

    test('network errors are wrapped', () async {
      final c = clientWith((_) async => throw http.ClientException('refused'));
      await expectLater(
          c.download('counts.json'),
          throwsA(isA<AiAgentBlocklistException>()
              .having((e) => e.status, 'status', isNull)
              .having((e) => e.message, 'message', contains('refused'))));
    });

    test('loadBlocklist parses aab_full.json', () async {
      final c = clientWith((_) async => http.Response(fixture, 200));
      final bl = await c.loadBlocklist();
      expect(bl.version, 'fixture-1');
      expect(bl.length, 12);
    });
  });

  group('conditional downloads', () {
    test('sidecar ETag, If-None-Match and 304', () async {
      final dir = tempDir();
      final path = '${dir.path}/domains.txt';
      final sent = <Map<String, String>>[];
      final c = clientWith((req) async {
        sent.add(req.headers);
        if (req.headers['If-None-Match'] == '"abc123"') {
          return http.Response('', 304);
        }
        return http.Response('example-agent.ai\n', 200,
            headers: {'etag': '"abc123"'});
      });

      expect(await c.downloadTo('domains.txt', path), isTrue);
      expect(File(path).readAsStringSync(), 'example-agent.ai\n');
      expect(File('$path.etag').readAsStringSync(), '"abc123"');
      expect(sent[0].containsKey('If-None-Match'), isFalse);

      expect(await c.downloadTo('domains.txt', path), isFalse);
      expect(sent[1]['If-None-Match'], '"abc123"');
      expect(File(path).readAsStringSync(), 'example-agent.ai\n');
      expect(
          dir.listSync().map((f) => f.uri.pathSegments.last).toList()..sort(),
          ['domains.txt', 'domains.txt.etag']);
    });

    test('weak -gzip ETag counts as unchanged', () async {
      final dir = tempDir();
      final path = '${dir.path}/hosts.txt';
      File(path).writeAsStringSync('0.0.0.0 example-agent.ai\n');
      File('$path.etag').writeAsStringSync('"5f2-63a"');
      final c = clientWith((_) async => http.Response('changed\n', 200,
          headers: {'etag': 'W/"5f2-63a-gzip"'}));
      expect(await c.downloadTo('hosts.txt', path), isFalse);
      expect(File(path).readAsStringSync(), '0.0.0.0 example-agent.ai\n');
    });

    test('a new ETag replaces the file', () async {
      final dir = tempDir();
      final path = '${dir.path}/hosts.txt';
      File(path).writeAsStringSync('old\n');
      File('$path.etag').writeAsStringSync('"v1"');
      final c = clientWith(
          (_) async => http.Response('new\n', 200, headers: {'etag': '"v2"'}));
      expect(await c.downloadTo('hosts.txt', path), isTrue);
      expect(File(path).readAsStringSync(), 'new\n');
      expect(File('$path.etag').readAsStringSync(), '"v2"');
    });

    test('sidecar is ignored when the file is missing', () async {
      final dir = tempDir();
      final path = '${dir.path}/proxy.pac';
      File('$path.etag').writeAsStringSync('"stale"');
      Map<String, String>? sent;
      final c = clientWith((req) async {
        sent = req.headers;
        return http.Response('function FindProxyForURL(u, h) {}', 200,
            headers: {'etag': '"stale"'});
      });
      expect(await c.downloadTo('proxy.pac', path), isTrue);
      expect(sent!.containsKey('If-None-Match'), isFalse);
      expect(File(path).existsSync(), isTrue);
    });

    test('bareEtag', () {
      expect(AiAgentBlocklistClient.bareEtag('W/"abc-gzip"'), 'abc');
      expect(AiAgentBlocklistClient.bareEtag('"abc"'), 'abc');
      expect(AiAgentBlocklistClient.bareEtag(' abc '), 'abc');
    });

    test('sync returns a map of updated files', () async {
      final dir = '${tempDir().path}/feed';
      final c = clientWith((req) async {
        if (req.headers['If-None-Match'] == '"same"') {
          return http.Response('', 304);
        }
        return http.Response('${req.url.pathSegments.last}\n', 200,
            headers: {'etag': '"same"'});
      });
      expect(await c.sync(dir, names: ['domains.txt', 'aab_full.json']),
          {'domains.txt': true, 'aab_full.json': true});
      expect(File('$dir/aab_full.json').readAsStringSync(), 'aab_full.json\n');
      expect(await c.sync(dir, names: ['domains.txt', 'aab_full.json']),
          {'domains.txt': false, 'aab_full.json': false});
      expect(AiAgentBlocklistClient.files, hasLength(19));
    });

    test('sync checks every name first', () async {
      final c = clientWith((_) => fail('no request expected'));
      await expectLater(
          c.sync(tempDir().path, names: ['domains.txt', '../x.txt']),
          throwsA(isA<AiAgentBlocklistException>()));
    });
  });

  group('Blocklist', () {
    test('fromFile and metadata', () {
      final bl = Blocklist.fromFile('test/fixtures/aab_full.json');
      expect(bl.product, 'AI Agent Blocklist');
      expect(bl.counts['total'], 12);
      expect(bl.entries.first.toJson().keys, BlocklistEntry.fields);
    });

    test('invalid documents', () {
      expect(() => Blocklist.fromJson('{"product": "x"}'),
          throwsA(isA<AiAgentBlocklistException>()));
      expect(() => Blocklist.fromJson('not json'),
          throwsA(isA<AiAgentBlocklistException>()));
      expect(() => Blocklist.fromFile('/nonexistent/aab_full.json'),
          throwsA(isA<AiAgentBlocklistException>()));
    });

    test('domain suffix matching on label boundaries', () {
      expect(list.checkDomain('example-agent.ai')?.toolName, 'Example Agent');
      expect(
          list.checkDomain('api.example-agent.ai')?.toolName, 'Example Agent');
      expect(list.checkDomain('a.b.c.example-agent.ai')?.toolName,
          'Example Agent');
      expect(list.checkDomain('notexample-agent.ai'), isNull);
      expect(list.checkDomain('example-agent.ai.other.test'), isNull);
      expect(list.checkDomain('ai'), isNull);
      expect(list.checkDomain(''), isNull);
    });

    test('URL normalisation', () {
      const cases = {
        'https://API.Example-Agent.ai/v1/run?x=1#top': 'api.example-agent.ai',
        'http://user:secret@sample-browser.app:8443/path': 'sample-browser.app',
        'sample-browser.app.': 'sample-browser.app',
        '  Demo-MCP-Server.dev:443  ': 'demo-mcp-server.dev',
        '//cdn.example-agent.ai/x.js': 'cdn.example-agent.ai',
        'wss://live.sample-browser.app/socket': 'live.sample-browser.app',
      };
      cases.forEach((input, host) {
        expect(Blocklist.normalizeHost(input), host);
        expect(list.checkDomain(input), isNotNull, reason: input);
      });
    });

    test('only kind domain counts for domain checks', () {
      expect(list.checkDomain('com.example.agentbrowser'), isNull);
      expect(list.domains(),
          ['demo-mcp-server.dev', 'example-agent.ai', 'sample-browser.app']);
    });

    test('extensions', () {
      expect(list.checkExtension('ABCDEFGHIJKLMNOPABCDEFGHIJKLMNOP')?.kind,
          'chrome_ext');
      expect(
          list.checkExtension('agent-helper@example.org')?.kind, 'firefox_ext');
      expect(
          list.checkExtension('examplecorp.example-coder')?.kind, 'vscode_ext');
      expect(list.checkExtension('abcdefghijklmnopabcdefghijklmno'), isNull);
      expect(list.checkExtension('example-agent.ai'), isNull);
    });

    test('processes with and without .exe', () {
      expect(list.checkProcess('samplebrowser')?.kind, 'process_win');
      expect(list.checkProcess('SAMPLEBROWSER.EXE')?.kind, 'process_win');
      expect(list.checkProcess('example-coder.exe')?.kind, 'process_cli');
      expect(list.checkProcess('sample browser helper')?.kind, 'process_mac');
      expect(list.checkProcess('example'), isNull);
    });

    test('packages: npm exact, PyPI normalised', () {
      expect(list.checkPackage('npm', 'Demo-MCP-Server')?.kind, 'npm');
      expect(list.checkPackage('npm', 'demo_mcp_server'), isNull);
      expect(list.checkPackage('pypi', 'demo-mcp-server')?.kind, 'pypi');
      expect(list.checkPackage('PyPI', 'DEMO__mcp..server')?.kind, 'pypi');
      expect(Blocklist.normalizePypi('Demo_MCP.Server'), 'demo-mcp-server');
      expect(() => list.checkPackage('cargo', 'demo'), throwsArgumentError);
    });

    test('check tries domains first, then identifiers', () {
      expect(list.check('https://www.sample-browser.app/download')?.kind,
          'domain');
      expect(list.check('COM.EXAMPLE.AGENTBROWSER')?.kind, 'mac_bundle_id');
      expect(list.check('agent-helper@example.org')?.kind, 'firefox_ext');
      expect(list.check('SampleBrowser.exe')?.kind, 'process_win');
      expect(list.check('nothing-here.example'), isNull);
    });

    test('filter and facets', () {
      expect(list.filter(agentType: 'AI browser'), hasLength(4));
      expect(
          list.filter(agentType: 'ai browser', kind: 'domain'), hasLength(1));
      expect(list.filter(riskGrade: 'High'), hasLength(3));
      expect(list.filter(agentType: 'Coding agent', riskGrade: 'Not graded'),
          hasLength(2));
      expect(list.filter(agentType: 'Voice agent'), isEmpty);
      expect(list.agentTypes(),
          ['AI browser', 'Browser agent', 'Coding agent', 'MCP server']);
      expect(list.kinds(), [
        'chrome_ext',
        'domain',
        'firefox_ext',
        'mac_bundle_id',
        'npm',
        'process_cli',
        'process_mac',
        'process_win',
        'pypi',
        'vscode_ext',
      ]);
    });

    test('entry JSON round trip', () {
      final e = list.checkDomain('example-agent.ai')!;
      expect(BlocklistEntry.fromJson(e.toJson()), e);
      expect(e.isDomain, isTrue);
    });
  });
}
