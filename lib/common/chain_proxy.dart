import 'package:fl_clash/common/yaml.dart';
import 'package:fl_clash/models/chain_proxy.dart';
import 'package:yaml/yaml.dart';

Object? _normalizeYaml(Object? value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _normalizeYaml(entry.value),
    };
  }
  if (value is YamlList) {
    return value.map(_normalizeYaml).toList();
  }
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _normalizeYaml(entry.value),
    };
  }
  if (value is List) {
    return value.map(_normalizeYaml).toList();
  }
  return value;
}

String chainProxyOutboundName(int profileId) =>
    '__FLCLASH_CHAIN_EXIT_$profileId';

List<dynamic> _selectedAppRules(
  Map<String, dynamic> raw,
  ChainProxySettings settings,
  String outboundName,
) {
  final packageNames = settings.appPackages
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  if (packageNames.isEmpty) {
    throw StateError('仅选中应用模式至少需要选择一个应用');
  }

  final originalMode = raw['mode']?.toString().trim().toLowerCase() ?? 'rule';
  final originalRules = List<dynamic>.from(
    raw['rules'] as List? ?? const <dynamic>[],
  );
  final appRules = packageNames
      .map((packageName) => 'PROCESS-NAME,$packageName,$outboundName')
      .toList();

  // PROCESS-NAME is intentionally used instead of UID. FlClash already
  // resolves Android package names for process rules, while UID routing has
  // had Android-version-specific issues. Put the app rules first so selected
  // packages cannot be captured by an earlier subscription rule.
  if (originalMode == 'direct') {
    return <dynamic>[...appRules, 'MATCH,DIRECT'];
  }

  // For rule mode preserve the subscription's entire routing policy for every
  // unselected app. If a profile has no rules, explicitly fall back to DIRECT
  // instead of accidentally making the residential chain global.
  if (originalMode == 'rule') {
    return <dynamic>[
      ...appRules,
      ...originalRules,
      if (originalRules.isEmpty) 'MATCH,DIRECT',
    ];
  }

  // Global mode does not have a portable rule-mode equivalent that preserves
  // the user's current GLOBAL selection across all Clash-compatible cores.
  // Preserve the subscription rule set instead of guessing a target. This is
  // deterministic and, most importantly, never expands the residential chain
  // beyond the explicitly selected applications.
  return <dynamic>[
    ...appRules,
    ...originalRules,
    if (originalRules.isEmpty) 'MATCH,DIRECT',
  ];
}

String applyChainProxyYaml(
  String sourceYaml,
  ChainProxySettings settings,
  int profileId,
) {
  if (!settings.enabled) return sourceYaml;
  if (!settings.isComplete) {
    throw StateError('链式代理配置不完整');
  }

  final parsed = loadYaml(sourceYaml);
  final normalized = _normalizeYaml(parsed);
  if (normalized is! Map<String, dynamic>) {
    throw StateError('无法解析当前代理配置');
  }

  final raw = Map<String, dynamic>.from(normalized);
  final proxies = List<dynamic>.from(raw['proxies'] as List? ?? const []);
  final groups = List<dynamic>.from(
    raw['proxy-groups'] as List? ?? const [],
  );

  final proxyNames = <String>{};
  for (final item in proxies) {
    if (item is Map && item['name'] != null) {
      proxyNames.add(item['name'].toString());
    }
  }
  final groupNames = <String>{};
  for (final item in groups) {
    if (item is Map && item['name'] != null) {
      groupNames.add(item['name'].toString());
    }
  }

  final sourceGroup = settings.sourceGroup.trim();
  if (!groupNames.contains(sourceGroup)) {
    throw StateError('机场代理组不存在：$sourceGroup');
  }

  final outboundName = chainProxyOutboundName(profileId);
  if (proxyNames.contains(outboundName) || groupNames.contains(outboundName)) {
    throw StateError('链式代理内部节点名称冲突：$outboundName');
  }

  final outbound = <String, dynamic>{
    'name': outboundName,
    'type': 'socks5',
    'server': settings.server.trim(),
    'port': settings.port,
    'udp': settings.udp,
    // Mihomo allows dialer-proxy to reference a proxy group. Binding the
    // residential exit to the selector means normal node switching inside
    // FlClash immediately changes the airport hop without touching this
    // chain configuration.
    'dialer-proxy': sourceGroup,
    if (settings.username.trim().isNotEmpty)
      'username': settings.username.trim(),
    if (settings.password.isNotEmpty) 'password': settings.password,
  };

  raw['proxies'] = [...proxies, outbound];

  if (settings.appMode == ChainProxyAppMode.selected) {
    raw['mode'] = 'rule';
    raw['rules'] = _selectedAppRules(raw, settings, outboundName);
    return yaml.encode(raw);
  }

  if (settings.strict) {
    // Leak-proof all-app mode: force the core into rule mode and route every
    // connection through the residential SOCKS5 outbound. Existing rule
    // routing is intentionally bypassed so no traffic silently exits via the
    // airport selector alone.
    raw['mode'] = 'rule';
    raw['rules'] = ['MATCH,$outboundName'];
  } else {
    final rules = List<String>.from(raw['rules'] as List? ?? const []);
    var replaced = false;
    for (var i = rules.length - 1; i >= 0; i--) {
      final parts = rules[i].split(',');
      if (parts.isNotEmpty && parts.first.trim().toUpperCase() == 'MATCH') {
        rules[i] = 'MATCH,$outboundName';
        replaced = true;
        break;
      }
    }
    if (!replaced) rules.add('MATCH,$outboundName');
    raw['rules'] = rules;
  }

  return yaml.encode(raw);
}
