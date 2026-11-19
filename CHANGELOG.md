## 1.0.0

First release.

- `AiAgentBlocklistClient` with a token from the constructor, the `AIAGENTBLOCKLIST_TOKEN` environment variable or `--dart-define`, checked before any request.
- `fileUrl()`, `fileListUrl`, `download()`, `downloadText()`, `downloadTo()` (ETag sidecar, If-None-Match, atomic rename), `sync()` and `loadBlocklist()`.
- `Blocklist.fromJson()`, `Blocklist.fromFile()` and `Blocklist.fromMap()` with `checkDomain()`, `checkExtension()`, `checkProcess()`, `checkPackage()`, `check()`, `filter()`, `domains()`, `agentTypes()` and `kinds()`. Lookup maps are built once.
- `BlocklistEntry` with the ten feed columns.
- Exceptions: `AiAgentBlocklistException` (with `status`), `NotFoundException`, `AccessEndedException`, `HttpStatusException`, `TokenException`. Network failures are wrapped in the base class.
- Works on Flutter mobile, desktop and the Dart VM; on the web the download and check functions work and the file helpers throw `UnsupportedError`.
