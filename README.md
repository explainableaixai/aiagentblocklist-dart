# aiagentblocklist for Dart and Flutter

IT teams build a surprising number of their own tools in Flutter: a desktop app the help desk uses to vet a request, a kiosk that checks lab machines, a small server that previews links for a chat system. This package gives those tools the AI Agent Blocklist as plain Dart objects. It syncs the daily feed from your private download link with conditional requests and runs every check locally, on the device or the server, with no lookup service in between.

```yaml
dependencies:
  aiagentblocklist: ^1.0.0
```

## Contents

- [Why a list of AI agents](#why-a-list-of-ai-agents)
- [Platform support](#platform-support)
- [Getting started](#getting-started)
- [Example A: a Flutter desktop admin app](#example-a-a-flutter-desktop-admin-app)
- [Example B: shelf middleware](#example-b-shelf-middleware)
- [Example C: a compiled sync tool for servers](#example-c-a-compiled-sync-tool-for-servers)
- [Example D: an extension policy from the JSON](#example-d-an-extension-policy-from-the-json)
- [API surface](#api-surface)
- [Exceptions](#exceptions)
- [FAQ](#faq)

## Why a list of AI agents

Agents differ from chat tools in one important way: they act. An AI browser can open tabs, follow links and submit forms, and a computer-use agent can move the pointer and type.

A coding agent can run shell commands. Each of them does this with the identity, sessions and network access of the person who installed it.

That borrowed access is the core problem. A company may have approved one assistant and reviewed its permissions, while a dozen others arrive as extensions, desktop apps or command-line tools nobody looked at. Our article on [AI agent identity and permissions](https://www.aiagentblocklist.com/ai-agents/ai-agent-identity-and-permissions.php) goes deeper into why the user's own access is what makes these tools sensitive.

We keep one list that covers the whole surface. Today that means 2,600+ AI agent domains and 5,300+ device identifiers, and a new build replaces the files every day without changing their links.

The same feed can drive a firewall, a resolver, a browser policy and your own Dart code. [ENISA](https://www.enisa.europa.eu/) publishes general guidance on managing this kind of technology risk in organisations.

## Platform support

The package uses `package:http` for downloads and conditional imports for anything that touches the file system.

| Platform | Download and parse | `downloadTo` / `sync` / `Blocklist.fromFile` | Token from environment |
|---|---|---|---|
| Dart VM (server, CLI) | yes | yes | yes |
| Flutter Windows, macOS, Linux | yes | yes | yes |
| Flutter Android and iOS | yes | yes (app storage) | via `--dart-define` |
| Flutter web | yes | throws `UnsupportedError` | via `--dart-define` |

On the web, browsers do not let scripts set the User-Agent header, so the package leaves it out there. Browsers also apply CORS rules, so most web builds will want a small backend that syncs the feed and serves `aab_full.json` to the app.

Flutter, Dart and the browser and operating system names above are used only to describe compatibility. Product names are trademarks of their respective owners.

## Getting started

Add the package with the tool you already use:

```bash
dart pub add aiagentblocklist
# or
flutter pub add aiagentblocklist
```

The client needs your 32-character token. It reads, in order: the `token` argument, the `AIAGENTBLOCKLIST_TOKEN` environment variable, and a compile-time define. A value that is not 32 letters and digits throws `TokenException` before any request.

```bash
export AIAGENTBLOCKLIST_TOKEN=YOUR32CHARACTERTOKENGOESHERE0000
dart run bin/tool.dart
# or bake it into a desktop build that only staff receive:
flutter build windows --dart-define=AIAGENTBLOCKLIST_TOKEN=YOUR32CHARACTERTOKENGOESHERE0000
```

Plans and access are described on the [pricing page](https://www.aiagentblocklist.com/pricing.php). Avoid shipping a token inside apps that go to the general public; for those, sync on a server you control and let the app fetch from there.

### A first check

```dart
import 'package:aiagentblocklist/aiagentblocklist.dart';

Future<void> main() async {
  final client = AiAgentBlocklistClient();
  final list = await client.loadBlocklist();
  client.close();

  print(list.checkDomain('https://app.example-agent.ai/start')?.agentType); // Browser agent
  print(list.checkExtension('abcdefghijklmnopabcdefghijklmnop')?.kind);    // chrome_ext
  print(list.checkProcess('SampleBrowser')?.platform);                     // windows
  print(list.check('com.example.agentbrowser')?.toolName);                 // Sample Browser
}
```

All the names here are invented for the examples. They have the same shape as real rows, so the code is unchanged when you load the live file.

## Example A: a Flutter desktop admin app

A help desk often gets questions like "can I install this extension?" or "is this site allowed?". A small desktop app with one text field answers them in seconds, and it works offline after the first sync.

The model syncs into the app support folder and parses the JSON on a background isolate, so a large file never stalls a frame:

```dart
import 'dart:isolate';

import 'package:aiagentblocklist/aiagentblocklist.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class BlocklistModel extends ChangeNotifier {
  Blocklist? list;
  String status = 'Not loaded';

  Future<void> refresh() async {
    final dir = (await getApplicationSupportDirectory()).path;
    final client = AiAgentBlocklistClient();
    try {
      final changed = await client.sync('$dir/aab', names: ['aab_full.json']);
      final path = '$dir/aab/aab_full.json';
      if (changed['aab_full.json']! || list == null) {
        list = await Isolate.run(() => Blocklist.fromFile(path));
      }
      status = 'Feed ${list!.version}, ${list!.length} entries';
    } on AccessEndedException {
      status = 'Subscription ended; using the last copy';
    } on AiAgentBlocklistException catch (e) {
      status = 'Offline: ${e.message}';
    } finally {
      client.close();
      notifyListeners();
    }
  }
}
```

The screen is a text field and a result card:

```dart
class CheckScreen extends StatefulWidget {
  const CheckScreen({super.key, required this.model});
  final BlocklistModel model;

  @override
  State<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends State<CheckScreen> {
  BlocklistEntry? hit;
  String query = '';

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextField(
        decoration: const InputDecoration(labelText: 'URL, extension ID, bundle ID or process'),
        onChanged: (v) => setState(() {
          query = v;
          hit = widget.model.list?.check(v);
        }),
      ),
      if (query.isNotEmpty)
        Card(
          child: ListTile(
            title: Text(hit == null ? 'Not on the list' : hit!.toolName),
            subtitle: Text(hit == null ? query : '${hit!.agentType} · ${hit!.kind} · ${hit!.platform}'),
          ),
        ),
      Text(widget.model.status),
    ]);
  }
}
```

Because `check()` tries domain rules first and exact identifiers second, one field handles a pasted URL, a Chrome extension ID, a macOS bundle ID and a Windows process name. Pair the app with our [list of AI browsers](https://www.aiagentblocklist.com/ai-browser-list.php) when staff want background on a result.

## Example B: shelf middleware

Servers built on `shelf` can refuse requests that try to reach an agent domain through them. Link preview services, redirectors and webhook relays are the usual candidates.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:aiagentblocklist/aiagentblocklist.dart';
import 'package:shelf/shelf.dart';

class BlocklistHolder {
  BlocklistHolder(this.path);
  final String path;
  Blocklist? _list;
  DateTime? _stamp;

  Blocklist get current {
    final stamp = File(path).lastModifiedSync();
    if (_list == null || stamp != _stamp) {
      _list = Blocklist.fromFile(path);
      _stamp = stamp;
    }
    return _list!;
  }
}

Middleware agentLinkGuard(BlocklistHolder holder, {String param = 'url'}) =>
    (Handler inner) => (Request request) {
          final target = request.url.queryParameters[param];
          final hit = target == null ? null : holder.current.checkDomain(target);
          if (hit != null) {
            return Response.forbidden(
              jsonEncode({'blocked': Blocklist.normalizeHost(target!), 'agent_type': hit.agentType}),
              headers: {'content-type': 'application/json'},
            );
          }
          return inner(request);
        };
```

```dart
final handler = const Pipeline()
    .addMiddleware(logRequests())
    .addMiddleware(agentLinkGuard(BlocklistHolder('/var/lib/aab/aab_full.json')))
    .addHandler(previewHandler);
```

The holder reloads when the file's modification time changes, so a separate sync job can update the feed while the server keeps running. The full runnable version lives in `example/shelf_guard.dart`. For the broader picture on MCP endpoints behind such services, see how to [block MCP servers](https://www.aiagentblocklist.com/mcp/block-mcp-servers.php).

## Example C: a compiled sync tool for servers

Many servers that need the feed have no Dart SDK. Compile the sync example once and copy a single binary:

```bash
dart compile exe example/sync_feed.dart -o aab-sync
scp aab-sync resolver01:/usr/local/bin/
```

Then schedule it with a systemd timer:

```ini
# /etc/systemd/system/aab-sync.service
[Service]
Type=oneshot
Environment=AIAGENTBLOCKLIST_TOKEN=YOUR32CHARACTERTOKENGOESHERE0000
ExecStart=/usr/local/bin/aab-sync /var/lib/aab

# /etc/systemd/system/aab-sync.timer
[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

The binary exits with 0 when done, 2 when the subscription has ended or is paused, and 1 for other failures, so the timer's status shows at a glance whether a person needs to act. Files arrive atomically, which matters for readers such as a resolver loading `dns_rpz.zone`; the zone follows standard [RFC 1035](https://www.rfc-editor.org/rfc/rfc1035) master file syntax.

## Example D: an extension policy from the JSON

The feed already ships ready-made policy files, but sometimes you want your own cut: only High and Severe grades, or only one agent type. `filter()` makes that a few lines:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:aiagentblocklist/aiagentblocklist.dart';

void main() {
  final list = Blocklist.fromFile('/var/lib/aab/aab_full.json');
  final ids = <String>{
    for (final grade in ['High', 'Severe'])
      for (final e in list.filter(kind: 'chrome_ext', riskGrade: grade)) e.ident,
  }.toList()
    ..sort();

  File('chrome_policy.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'ExtensionInstallBlocklist': ids}));
  stdout.writeln('${ids.length} extension IDs written');
}
```

Our write-up on [AI browser security risks](https://www.aiagentblocklist.com/ai-browsers/ai-browser-security-risks.php) can help when deciding which grades belong in a first rollout.

## API surface

### `AiAgentBlocklistClient`

| Member | Type | Description |
|---|---|---|
| `AiAgentBlocklistClient({token, baseUrl, timeout, userAgent, httpClient})` | constructor | Default timeout 30 seconds. Pass `httpClient` to reuse one or to mock it. |
| `fileListUrl` | `Uri` | Address of your file index (an HTML page). |
| `fileUrl(name)` | `Uri` | Download address for a single file, after a name check. |
| `download(name)` | `Future<Uint8List>` | Raw bytes of one file. |
| `downloadText(name)` | `Future<String>` | The same, decoded as UTF-8. |
| `downloadTo(name, path)` | `Future<bool>` | Conditional GET with a `<path>.etag` sidecar; resolves to `true` only if it replaced the local copy. |
| `sync(dir, {names})` | `Future<Map<String, bool>>` | Runs `downloadTo` over the given names, or over every published file if you pass none. |
| `loadBlocklist()` | `Future<Blocklist>` | Downloads and parses `aab_full.json`. |
| `close()` | `void` | Closes the HTTP client this instance created. |
| `files`, `bareEtag()`, `checkFileName()` | static | File names, ETag helper, name validation. |

### `Blocklist`

| Member | Type | Description |
|---|---|---|
| `Blocklist.fromJson(text)`, `.fromFile(path)`, `.fromMap(map)` | factories | Build from text, a local file or decoded JSON. |
| `version`, `product`, `counts`, `entries` | fields | Feed metadata and rows; also an `Iterable<BlocklistEntry>`. |
| `checkDomain(hostOrUrl)` | `BlocklistEntry?` | Host and every parent domain; kind `domain` only. |
| `checkExtension(id)` | `BlocklistEntry?` | Browser and IDE extension IDs, case-insensitive. |
| `checkProcess(name)` | `BlocklistEntry?` | Process names; `.exe` optional on either side. |
| `checkPackage(ecosystem, name)` | `BlocklistEntry?` | `npm` exact, `pypi` with PEP 503 normalisation. |
| `check(identifier)` | `BlocklistEntry?` | Domains first, then any exact identifier. |
| `filter({agentType, kind, riskGrade})` | `List<BlocklistEntry>` | Case-insensitive match on every given field. |
| `domains()`, `agentTypes()`, `kinds()` | `List<String>` | Sorted distinct values. |
| `normalizeHost()`, `normalizePypi()` | static | The normalisers the checks use. |

`BlocklistEntry` exposes the ten columns as camelCase fields (`toolName`, `toolDomain`, `category`, `subcategory`, `agentType`, `kind`, `ident`, `name`, `platform`, `riskGrade`), with `toJson()` returning the original snake_case keys and value equality.

## Exceptions

All errors extend `AiAgentBlocklistException`, which carries `message` and a nullable `status`.

| Type | Cause | `status` |
|---|---|---|
| `TokenException` | missing or malformed token, thrown in the constructor | `null` |
| `NotFoundException` | unknown token or file name | `404` |
| `AccessEndedException` | subscription ended or paused | `403` |
| `HttpStatusException` | any other non-2xx answer | that status |
| `AiAgentBlocklistException` | invalid file name, timeout, socket error, bad JSON | `null` |

```dart
try {
  await client.sync(dir);
} on AccessEndedException {
  showBanner('Feed access has ended. Checks use the last downloaded copy.');
} on NotFoundException {
  showBanner('The download token was not recognised.');
} on AiAgentBlocklistException catch (e) {
  log('sync failed, will retry: $e');
}
```

Messages never contain the token, and the client's `toString()` hides it as well.

## Identifier kinds in the feed

| `kind` | What `ident` holds | Checked by |
|---|---|---|
| `domain` | a registrable domain or host | `checkDomain`, `check` |
| `chrome_ext`, `edge_ext` | a 32-letter extension ID | `checkExtension` |
| `firefox_ext` | an add-on ID such as `name@example.org` | `checkExtension` |
| `vscode_ext`, `openvsx_ext`, `jetbrains_plugin` | an IDE plugin ID | `checkExtension` |
| `mac_bundle_id`, `mac_app_store` | a bundle or store ID | `check` |
| `process_mac`, `process_win`, `process_cli` | a process or command name | `checkProcess` |
| `winget`, `ms_store` | a Windows package ID | `check` |
| `brew_cask`, `brew_formula` | a Homebrew name | `check` |
| `npm`, `pypi` | a package name | `checkPackage` |

The `agentType` field says what the tool does (AI browser, Coding agent, MCP server, Voice agent and so on). `riskGrade` is one of Low, Moderate, Elevated, High, Severe or "Not graded".

## A few of the files

| File | Format |
|---|---|
| `aab_full.json` | `{"product","version","counts","columns","entries"}` |
| `hosts.txt` | `0.0.0.0 domain` lines, in the classic [hosts file](https://en.wikipedia.org/wiki/Hosts_(file)) format |
| `dns_rpz.zone` | response policy zone answering NXDOMAIN |
| `chrome_edge_extensions.mobileconfig` | macOS profile for both browsers |
| `chrome_edge_extension_blocklist.reg` | Windows registry file for both browsers |
| `windows_package_ids.txt` | winget and Microsoft Store IDs |
| `process_names.txt` | process and command names |

Nineteen files in total; `AiAgentBlocklistClient.files` lists them all.

## Performance notes

- Parsing builds lookup maps once. After that, a domain check costs one map lookup per label, and the other checks cost one lookup each.
- In Flutter, parse with `Isolate.run` as in Example A. On a server, parse at start-up and reload on file change.
- Keep one `Blocklist` per process. Rebuilding it per request wastes memory and time.

## Behind a corporate proxy

Dart's `HttpClient` connects directly unless you tell it otherwise; it does not read `HTTPS_PROXY` by default. Pass an `IOClient` that does:

```dart
import 'dart:io';

import 'package:http/io_client.dart';

final inner = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
final client = AiAgentBlocklistClient(httpClient: IOClient(inner));
```

`findProxyFromEnvironment` honours `https_proxy`, `http_proxy` and `no_proxy`. Since you passed the HTTP client in, close it yourself when the work is done.

## Where files and tokens live

- **Desktop builds.** `getApplicationSupportDirectory()` gives a per-user folder that survives updates. Keep the feed there, not next to the executable, which is often read-only.
- **Mobile builds.** App storage works the same way. The JSON is a few megabytes, so a sync on Wi-Fi only is a reasonable default.
- **Servers.** Use a fixed folder such as `/var/lib/aab`, owned by the sync user and readable by the services that load it.
- **Tokens.** A token compiled in with `--dart-define` can be read back from the binary. That is fine for an internal admin tool and a poor fit for anything public.

## Testing

Inject a `MockClient` from `package:http/testing.dart`:

```dart
final client = AiAgentBlocklistClient(
  token: 'a' * 32,
  httpClient: MockClient((req) async => http.Response(fixtureJson, 200, headers: {'etag': '"t1"'})),
);
```

Code that only checks can skip the client and use `Blocklist.fromJson()` with a small fixture. `dart test` runs this package's own suite offline.

## FAQ

### Can a Flutter web app use it?

Yes for parsing and checks. File helpers throw `UnsupportedError` on the web, and browsers will usually need the JSON served from your own origin.

### Do I need to call close()?

Only when the client created its own HTTP client, which is the default. If you passed `httpClient`, you own its lifetime.

### How do I keep the feed current in a desktop app?

Call `sync()` at start-up and then on a `Timer.periodic`, for example every few hours. Unchanged files return 304 and cost almost nothing.

### What is the difference between check() and checkDomain()?

`checkDomain()` only looks at domain rows and walks parent domains. `check()` does that first and then tries an exact match against every other identifier kind.

### Is the feed a good fit for computer-use agents?

Yes, as one layer. Those agents ship as desktop apps, extensions and cloud services, and the feed lists identifiers for all three. See our notes on [computer-use agent security](https://www.aiagentblocklist.com/ai-agents/computer-use-agents-security.php).

### How do we decide which agents to allow?

Start with an inventory, then score each agent for what it can reach. Our [AI agent risk assessment guide](https://www.aiagentblocklist.com/guides/ai-agent-risk-assessment.php) offers a simple template.

### Does a failed sync break the app?

No. A failure throws before anything is replaced, so the last good files stay on disk. The admin app in Example A keeps answering from that copy and shows the error in its status line.

### Where do MCP servers fit?

They appear as domains, npm and PyPI packages, and IDE plugins, tagged with the agent type "MCP server". The [Model Context Protocol](https://modelcontextprotocol.io/) site explains what these servers do.

## Links

- Source: [github.com/explainableaixai/aiagentblocklist-dart](https://github.com/explainableaixai/aiagentblocklist-dart)
- Package: [pub.dev/packages/aiagentblocklist](https://pub.dev/packages/aiagentblocklist)
- Questions and corrections: [contact us](https://www.aiagentblocklist.com/contact.php) or info@alpha-quantum.com

## License

You may use this package under the terms of the MIT License. Copyright (c) 2026 Alpha Quantum, as stated in `LICENSE`.

## Related

Our sister lists: an [AI tools blocklist](https://www.aitoolsblocklist.com) for AI tools in general, an [app blocklist for MDM](https://www.appblocklist.com) for mobile apps, and a [web filtering database](https://www.webfilteringdatabase.com) for website categories.
