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

// Keep the protected resolver set compatible with FlClash's own Android
// defaults. These DoH endpoints are reachable before the airport/residential
// chain exists, which avoids making proxy-node resolution depend on the chain
// that is still being established.
const _privacyDnsServers = <String>[
  'https://doh.pub/dns-query',
  'https://dns.alidns.com/dns-query',
];

// Mihomo uses default-nameserver only to bootstrap DNS-server hostnames. The
// actual application and proxy-node domain questions still go to the encrypted
// DoH resolvers above. Keeping this tiny bootstrap path is intentional: using
// remote encrypted resolvers here previously made Android lose all node DNS
// when those endpoints were unreachable before the tunnel was ready.
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

  // Preserve FlClash/Mihomo structural DNS fields such as listen,
  // enhanced-mode, fake-ip-range and fake-ip-filter. They are part of the
  // Android TUN DNS path and replacing them wholesale can break DNS hijacking.
  // Only remove resolver branches that could send real domain questions to an
  // inherited subscription resolver outside our protected resolver set.
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
  dns['listen'] ??= '0.0.0.0:1053';
  dns['prefer-h3'] = false;
  dns['use-system-hosts'] = false;

  // Do not make DNS transport follow proxy rules here. Android already sends
  // system DNS to the VPN's synthetic resolver and the TUN layer hijacks port
  // 53. Keeping upstream DoH independent from proxy rules prevents the
  // node-DNS -> proxy -> node-DNS bootstrap cycle that caused every delay test
  // to time out on real devices.
  dns['respect-rules'] = false;
  dns['nameserver'] = List<String>.from(_privacyDnsServers);
  dns['proxy-server-nameserver'] = List<String>.from(_privacyDnsServers);
  dns['default-nameserver'] = List<String>.from(_bootstrapResolverIps);

  // A plain subscription often has no DNS section at all. In that case use the
  // same structural defaults as FlClash instead of relying on Mihomo implicit
  // defaults, so Android TUN DNS handling stays deterministic.
  dns.putIfAbsent('enhanced-mode', () => 'fake-ip');
  dns.putIfAbsent('fake-ip-range', () => '198.18.0.1/16');
  dns.putIfAbsent(
    'fake-ip-filter',
    () => <String>['*.lan', 'localhost.ptlogin2.qq.com'],
  );

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
