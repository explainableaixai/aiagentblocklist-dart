/// One row of the feed, with the ten columns of aab_full.csv and aab_full.json.
class BlocklistEntry {
  /// Creates an entry. Missing values are empty strings.
  const BlocklistEntry({
    this.toolName = '',
    this.toolDomain = '',
    this.category = '',
    this.subcategory = '',
    this.agentType = '',
    this.kind = '',
    this.ident = '',
    this.name = '',
    this.platform = '',
    this.riskGrade = '',
  });

  /// Builds an entry from a decoded JSON object or a CSV row map.
  factory BlocklistEntry.fromJson(Map<String, dynamic> json) {
    String s(String key) => json[key]?.toString() ?? '';
    return BlocklistEntry(
      toolName: s('tool_name'),
      toolDomain: s('tool_domain'),
      category: s('category'),
      subcategory: s('subcategory'),
      agentType: s('agent_type'),
      kind: s('kind'),
      ident: s('ident'),
      name: s('name'),
      platform: s('platform'),
      riskGrade: s('risk_grade'),
    );
  }

  /// The column names, in feed order.
  static const List<String> fields = [
    'tool_name',
    'tool_domain',
    'category',
    'subcategory',
    'agent_type',
    'kind',
    'ident',
    'name',
    'platform',
    'risk_grade',
  ];

  /// Product name.
  final String toolName;

  /// Main domain of the product.
  final String toolDomain;

  /// Category.
  final String category;

  /// Subcategory.
  final String subcategory;

  /// Agent type, for example "AI browser" or "MCP server".
  final String agentType;

  /// Identifier kind, for example "domain", "chrome_ext" or "process_win".
  final String kind;

  /// The identifier itself (domain, extension ID, bundle ID, process name...).
  final String ident;

  /// Display name of this identifier.
  final String name;

  /// Platform of this identifier.
  final String platform;

  /// Low, Moderate, Elevated, High, Severe or "Not graded".
  final String riskGrade;

  /// True for rows of kind `domain`.
  bool get isDomain => kind == 'domain';

  /// The entry with the original snake_case keys.
  Map<String, String> toJson() => {
        'tool_name': toolName,
        'tool_domain': toolDomain,
        'category': category,
        'subcategory': subcategory,
        'agent_type': agentType,
        'kind': kind,
        'ident': ident,
        'name': name,
        'platform': platform,
        'risk_grade': riskGrade,
      };

  @override
  String toString() => 'BlocklistEntry($kind: $ident, $toolName, $agentType)';

  @override
  bool operator ==(Object other) =>
      other is BlocklistEntry &&
      other.kind == kind &&
      other.ident == ident &&
      other.toolName == toolName &&
      other.toolDomain == toolDomain &&
      other.agentType == agentType &&
      other.riskGrade == riskGrade &&
      other.name == name &&
      other.platform == platform &&
      other.category == category &&
      other.subcategory == subcategory;

  @override
  int get hashCode => Object.hash(kind, ident, toolName, toolDomain, agentType,
      riskGrade, name, platform, category, subcategory);
}
