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

String chainProxyUpstreamName(int profileId, int index) =>
    '__FLCLASH_CHAIN_UPSTREAM_${profileId}_$index';

String chainProxyFallbackName(int profileId, int index) =>
    '__FLCLASH_CHAIN_EXIT_${profileId}_$index';

const _nonProxyTypes = <String>{
  'direct',
  'reject',
  'reject-drop',
  'pass',
  'dns',
};

// Normal application DNS. These resolver transports follow routing rules, so
// once the airport -> residential SOCKS5 chain is up, ordinary DNS leaves via
// that chain instead of the Android network.
const _privacyDnsServers = <String>[
  'https://1.1.1.1/dns-query',
  'https://8.8.8.8/dns-query',
];

// Proxy-node bootstrap DNS must be reachable before the chain itself exists.
// Use mainland-reachable encrypted resolvers and force their transport DIRECT;
// they are only used to resolve airport/residential proxy server hostnames.
const _proxyBootstrapDnsServers = <String>[
  'https://doh.pub/dns-query#DIRECT',
  'https://dns.alidns.com/dns-query#DIRECT',
];

// Mihomo requires IP resolvers for resolving DNS-server hostnames. These only
// bootstrap doh.pub/dns.alidns.com; ordinary application domains never use
// these resolvers directly.
const _bootstrapResolverIps = <String>[
  '223.5.5.5',
  '119.29.29.29',
];

bool _isChainableProxy(Map<String, dynamic> proxy) {
  final name = proxy['name']?.toString().trim() ?? '';
  final type = proxy['type']?.toString().trim().toLowerCase() ?? '';
  return name.isNotEmpty &&
      !_nonProxyTypes.contains(type) &&
      !name.startsWith('__FLCLASH_CHAIN_');
}

Map<String, dynamic> _landingProxy(
  String name,
  String dialer,
  ChainProxySettings settings,
) {
  return <String, dynamic>{
    'name': name,
    'type': 'socks5',
    'server': settings.server.trim(),
    'port': settings.port,
    'udp': settings.udp,
    'dialer-proxy': dialer,
    if (settings.username.trim().isNotEmpty)
      'username': settings.username.trim(),
    if (settings.password.isNotEmpty) 'password': settings.password,
  };
}

void _applyDnsLeakProtection(Map<String, dynamic> raw) {
  final current = raw['dns'];
  final dns = current is Map
      ? Map<String, dynamic>.from(current)
      : <String, dynamic>{};

  // Strict mode owns the resolver graph. Remove inherited resolver branches
  // that could fall back to a subscription-provided or Android system resolver.
  for (final key in const <String>[
    'nameserver-policy',
    'proxy-server-nameserver-policy',
    'direct-nameserver',
    'direct-nameserver-follow-policy',
    'fallback',
    'fallback-filter',
  ]) {
    dns.remove(key);
  }

  dns['enable'] = true;
  dns['prefer-h3'] = false;
  dns['use-system-hosts'] = false;

  // Ordinary DNS follows the active routing rules. Proxy-server DNS is kept on
  // a separate DIRECT encrypted bootstrap path so node hostnames can be
  // resolved before the chain exists. This is the split Mihomo expects to
  // avoid the proxy/DNS chicken-and-egg failure on Android.
  dns['respect-rules'] = true;
  dns['nameserver'] = List<String>.from(_privacyDnsServers);
  dns['proxy-server-nameserver'] = List<String>.from(
    _proxyBootstrapDnsServers,
  );
  dns['default-nameserver'] = List<String>.from(_bootstrapResolverIps);
  raw['dns'] = dns;
}

bool _hasDynamicProxySources(Map<String, dynamic> raw, List<dynamic> groups) {
  final providers = raw['proxy-providers'];
  if (providers is Map && providers.isNotEmpty) return true;

  for (final item in groups) {
    if (item is! Map) continue;
    final group = Map<String, dynamic>.from(item);
    final use = group['use'];
    if (use is List && use.isNotEmpty) return true;
    if (group['include-all'] == true ||
        group['include-all-proxies'] == true ||
        group['include-all-providers'] == true) {
      return true;
    }
  }
  return false;
}

String? _getRuleProxyTarget(String rule, Set<String> knownTargets) {
  final parts = rule.split(',');
  if (parts.length < 2) return null;

  var targetIndex = parts.length - 1;
  if (parts[targetIndex].trim().toLowerCase() == 'no-resolve') {
    targetIndex--;
  }
  if (targetIndex < 1) return null;

  final target = parts[targetIndex].trim();
  return knownTargets.contains(target) ? target : null;
}

String _rewriteRuleProxyTarget(
  String rule,
  String target,
  String outboundName,
) {
  final parts = rule.split(',');
  var targetIndex = parts.length - 1;
  if (parts[targetIndex].trim().toLowerCase() == 'no-resolve') {
    targetIndex--;
  }
  if (targetIndex < 1 || parts[targetIndex].trim() != target) return rule;
  parts[targetIndex] = outboundName;
  return parts.join(',');
}

void _applyDynamicSourceCompatibility(
  Map<String, dynamic> raw,
  List<dynamic> proxies,
  List<dynamic> groups,
  ChainProxySettings settings,
  int profileId,
) {
  final rules = List<dynamic>.from(raw['rules'] as List? ?? const []);
  if (rules.isEmpty) {
    throw StateError('动态代理源暂不支持无规则模式的链式落地代理');
  }

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
  final knownTargets = <String>{...proxyNames, ...groupNames};

  final usedTargets = <String>{};
  for (final item in rules) {
    if (item is! String) continue;
    final target = _getRuleProxyTarget(item, knownTargets);
    if (target != null) usedTargets.add(target);
  }
  if (usedTargets.isEmpty) {
    throw StateError('当前规则没有可链式代理的代理目标');
  }

  final sortedTargets = usedTargets.toList()..sort();
  final targetOutbounds = <String, String>{};
  final outbounds = <Map<String, dynamic>>[];
  final existingNames = <String>{...proxyNames, ...groupNames};

  for (var i = 0; i < sortedTargets.length; i++) {
    final target = sortedTargets[i];
    final outboundName = chainProxyFallbackName(profileId, i);
    if (!existingNames.add(outboundName)) {
      throw StateError('链式代理内部节点名称冲突：$outboundName');
    }
    targetOutbounds[target] = outboundName;
    outbounds.add(_landingProxy(outboundName, target, settings));
  }

  raw['mode'] = 'rule';
  raw['proxies'] = [...proxies, ...outbounds];
  raw['rules'] = rules.map((item) {
    if (item is! String) return item;
    final target = _getRuleProxyTarget(item, knownTargets);
    if (target == null) return item;
    final outboundName = targetOutbounds[target];
    if (outboundName == null) return item;
    return _rewriteRuleProxyTarget(item, target, outboundName);
  }).toList();
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
  final groups = List<dynamic>.from(raw['proxy-groups'] as List? ?? const []);

  if (settings.dnsLeakProtection) {
    _applyDnsLeakProtection(raw);
  }

  if (_hasDynamicProxySources(raw, groups)) {
    _applyDynamicSourceCompatibility(
      raw,
      proxies,
      groups,
      settings,
      profileId,
    );
    return yaml.encode(raw);
  }

  final existingNames = <String>{};
  for (final item in proxies) {
    if (item is Map && item['name'] != null) {
      existingNames.add(item['name'].toString());
    }
  }
  for (final item in groups) {
    if (item is Map && item['name'] != null) {
      existingNames.add(item['name'].toString());
    }
  }

  final transformed = <dynamic>[];
  var chainIndex = 0;
  for (final item in proxies) {
    if (item is! Map) {
      transformed.add(item);
      continue;
    }

    final proxy = Map<String, dynamic>.from(item);
    if (!_isChainableProxy(proxy)) {
      transformed.add(proxy);
      continue;
    }

    final publicName = proxy['name'].toString();
    final upstreamName = chainProxyUpstreamName(profileId, chainIndex++);
    if (!existingNames.add(upstreamName)) {
      throw StateError('链式代理内部节点名称冲突：$upstreamName');
    }

    final upstream = Map<String, dynamic>.from(proxy)..['name'] = upstreamName;
    transformed.add(_landingProxy(publicName, upstreamName, settings));
    transformed.add(upstream);
  }

  if (chainIndex == 0) {
    throw StateError('当前配置没有可链式代理的节点');
  }

  raw['proxies'] = transformed;
  return yaml.encode(raw);
}
