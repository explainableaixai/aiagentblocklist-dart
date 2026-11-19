// A shelf middleware that refuses requests whose `url` query parameter (or
// JSON field) points at a listed AI agent domain, for example on a link
// preview or redirect service. The blocklist reloads from disk when the
// synced file changes.
//
//   dart run example/shelf_guard.dart /var/lib/aab/aab_full.json
//   curl 'http://localhost:8080/preview?url=https://api.example-agent.ai/'
import 'dart:convert';
import 'dart:io';

import 'package:aiagentblocklist/aiagentblocklist.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Holds the current blocklist and reloads it when the file's mtime changes.
class BlocklistHolder {
  BlocklistHolder(this.path);

  final String path;
  Blocklist? _list;
  DateTime? _loadedMtime;

  Blocklist get current {
    final mtime = File(path).lastModifiedSync();
    if (_list == null || mtime != _loadedMtime) {
      _list = Blocklist.fromFile(path);
      _loadedMtime = mtime;
    }
    return _list!;
  }
}

Middleware agentLinkGuard(BlocklistHolder holder, {String param = 'url'}) {
  return (Handler inner) {
    return (Request request) {
      final target = request.url.queryParameters[param];
      if (target != null && target.isNotEmpty) {
        final hit = holder.current.checkDomain(target);
        if (hit != null) {
          return Response.forbidden(
            jsonEncode({
              'blocked': Blocklist.normalizeHost(target),
              'agent_type': hit.agentType,
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      }
      return inner(request);
    };
  };
}

Future<void> main(List<String> args) async {
  final holder =
      BlocklistHolder(args.isEmpty ? 'aab-feed/aab_full.json' : args.first);
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(agentLinkGuard(holder))
      .addHandler((request) => Response.ok('preview would render here\n'));

  final server =
      await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 8080);
  stdout.writeln('Listening on http://${server.address.host}:${server.port}');
}
