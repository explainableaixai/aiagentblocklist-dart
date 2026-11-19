// Keep a folder of feed files current; run it from cron, a systemd timer or
// a scheduled task. Compile once with `dart compile exe` for servers that
// have no Dart SDK.
//
//   AIAGENTBLOCKLIST_TOKEN=... dart run example/sync_feed.dart /var/lib/aab
//
// Exit codes: 0 done, 2 subscription ended or paused, 1 other failure.
import 'dart:io';

import 'package:aiagentblocklist/aiagentblocklist.dart';

const wanted = [
  'aab_full.json',
  'domains.txt',
  'firewall_edl.txt',
  'chrome_extension_blocklist.json',
  'edge_extension_blocklist.json',
];

Future<void> main(List<String> args) async {
  final dir = args.isEmpty ? 'aab-feed' : args.first;
  final client = AiAgentBlocklistClient(timeout: const Duration(seconds: 60));
  try {
    final result = await client.sync(dir, names: wanted);
    result.forEach((name, updated) => stdout
        .writeln('${name.padRight(34)} ${updated ? 'updated' : 'unchanged'}'));
  } on AccessEndedException {
    stderr.writeln('Subscription ended or paused; keeping the last files.');
    exitCode = 2;
  } on AiAgentBlocklistException catch (e) {
    stderr.writeln('Sync failed: $e');
    exitCode = 1;
  } finally {
    client.close();
  }
}
