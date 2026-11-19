// Check URLs, extension IDs, bundle IDs or process names against the feed.
//
//   AIAGENTBLOCKLIST_TOKEN=... dart run example/example.dart \
//       https://api.example-agent.ai/run com.example.agentbrowser
//
// Pass --file path/to/aab_full.json as the first two arguments to work
// offline from a synced copy instead of downloading.
import 'dart:io';

import 'package:aiagentblocklist/aiagentblocklist.dart';

Future<void> main(List<String> args) async {
  var inputs = args;
  Blocklist list;
  AiAgentBlocklistClient? client;

  try {
    if (args.length >= 2 && args.first == '--file') {
      list = Blocklist.fromFile(args[1]);
      inputs = args.sublist(2);
    } else {
      client = AiAgentBlocklistClient();
      list = await client.loadBlocklist();
    }
  } on AiAgentBlocklistException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
    return;
  } finally {
    client?.close();
  }

  stdout.writeln('Feed ${list.version}: ${list.length} entries, '
      '${list.domains().length} domains');
  for (final item in inputs) {
    final hit = list.check(item);
    stdout.writeln(hit == null
        ? 'ok      $item'
        : 'LISTED  $item  ${hit.toolName} | ${hit.agentType} | ${hit.kind}');
  }
}
