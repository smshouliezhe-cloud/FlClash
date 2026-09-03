class WindowsProxyChainSettings {
  final bool enabled;
  final List<String> nodes;
  final String targetGroup;

  const WindowsProxyChainSettings({
    this.enabled = false,
    this.nodes = const [],
    this.targetGroup = '',
  });

  bool get isComplete =>
      nodes.length >= 2 &&
      nodes.toSet().length == nodes.length &&
      targetGroup.trim().isNotEmpty;

  WindowsProxyChainSettings copyWith({
    bool? enabled,
    List<String>? nodes,
    String? targetGroup,
  }) {
    return WindowsProxyChainSettings(
      enabled: enabled ?? this.enabled,
      nodes: nodes ?? this.nodes,
      targetGroup: targetGroup ?? this.targetGroup,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'nodes': nodes,
    'targetGroup': targetGroup,
  };

  factory WindowsProxyChainSettings.fromJson(Map<String, Object?> json) {
    final rawNodes = json['nodes'];
    final nodes = rawNodes is List
        ? rawNodes
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return WindowsProxyChainSettings(
      enabled: json['enabled'] == true,
      nodes: nodes,
      targetGroup: json['targetGroup'] as String? ?? '',
    );
  }
}
