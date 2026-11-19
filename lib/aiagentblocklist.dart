/// Feed client for the AI Agent Blocklist (https://www.aiagentblocklist.com).
///
/// ```dart
/// final client = AiAgentBlocklistClient(); // reads AIAGENTBLOCKLIST_TOKEN
/// final list = await client.loadBlocklist();
/// print(list.checkDomain('https://api.example-agent.ai/run')?.agentType);
/// client.close();
/// ```
library;

export 'src/blocklist.dart';
export 'src/client.dart';
export 'src/entry.dart';
export 'src/exceptions.dart';
