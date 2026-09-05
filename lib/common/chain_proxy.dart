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

String chainProxyPrivacyGroupName(int profileId) =>
    '__FLCLASH_CHAIN_PRIVACY_$profileId';

const _nonProxyTypes = <String>{
  'direct',
  'reject',
  'reject-drop',
  'pass',
  'dns',
};

// Application DNS uses encrypted public resolvers. In Android strict privacy
// mode these endpoints are explicitly bound to the chain privacy group, so the
// resolver sees the residential egress instead of the phone's physical IP.
const _privacyDnsServers = <String>[
  'https://doh.pub/dns-query',
  'https://dns.alidns.com/dns-query',
];

// default-nameserver only bootstraps DNS-server hostnames. Use IP-hosted DoH so
// even the bootstrap path does not emit plaintext UDP/53 queries. AliDNS
// supports RFC 8484 on these IP endpoints and they are reachable in mainland
// networks where remote bootstrap resolvers can be unreliable.
const _bootstrapDnsServers = <String>[
  'https://223.5.5.5/dns-query',
  'https://223.6.6.6/dns-query',
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
  // that can send real application-domain questions outside the protected path.
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
  dns['respect-rules'] = false;
  dns['nameserver'] = List<String>.from(_privacyDnsServers);
  dns['proxy-server-nameserver'] = List<String>.from(_privacyDnsServers);
  dns['default-nameserver'] = List<String>.from(_bootstrapDnsServers);

  // A plain subscription often has no DNS section. Keep the same structural
  // defaults as FlClash so Android TUN DNS handling stays deterministic.
  dns.putIfAbsent('enhanced-mode', () => 'fake-ip');
  dns.putIfAbsent('fake-ip-range', () => '198.18.0.1/16');
  dns.putIfAbsent(
    'fake-ip-filter',
    () => <String>['*.lan', 'localhost.ptlogin2.qq.com'],
  );

  raw['dns'] = dns;
}

void _applyAndroidTunnelPrivacy(Map<String, dynamic> raw) {
  final current = raw['tun'];
  final tun = current is Map
      ? Map<String, dynamic>.from(current)
      : <String, dynamic>{};

  // Do not silently claim whole-device protection when the Android VPN/TUN is
  // disabled. Failing profile construction is safer than serving the previous
  // or a partially protected profile.
  if (tun['enable'] != true) {
    throw StateError('Android 防泄漏模式需要先开启 TUN 模式');
  }

  final hijack = <String>[
    for (final item in (tun['dns-hijack'] as List? ?? const []))
      item.toString(),
  ];
  for (final entry in const <String>['any:53', 'tcp://any:53']) {
    if (!hijack.contains(entry)) hijack.add(entry);
  }

  tun['dns-hijack'] = hijack;
  // Mihomo documents strict-route as the Android switch that prevents address
  // leaks and makes DNS hijacking effective with TUN routing.
  tun['strict-route'] = true;
  raw['tun'] = tun;
}

void _bindDnsToPrivacyGroup(Map<String, dynamic> raw, String privacyGroup) {
  final current = raw['dns'];
  if (current is! Map) return;
  final dns = Map<String, dynamic>.from(current);

  // Mihomo DNS URL fragments can name a proxy/group. Binding the application
  // resolvers directly avoids DIRECT rules for the DoH endpoints and avoids the
  // RULES bootstrap cycle that previously made Android node tests time out.
  dns['nameserver'] = _privacyDnsServers
      .map((server) => '$server#$privacyGroup')
      .toList();
  raw['dns'] = dns;
}

void _applyAndroidPrivacyRouting(
  Map<String, dynamic> raw,
  ChainProxySettings settings,
  int profileId,
  List<String> landingTargets,
) {
  if (landingTargets.isEmpty) {
    throw StateError('Android 防泄漏模式没有可用的住宅落地链路');
  }

  final privacyGroup = chainProxyPrivacyGroupName(profileId);
  final groups = List<dynamic>.from(
    raw['proxy-groups'] as List? ?? const <dynamic>[],
  );
  final hasConflict = groups.any(
    (item) => item is Map && item['name']?.toString() == privacyGroup,
  );
  if (hasConflict) {
    throw StateError('链式代理内部节点名称冲突：$privacyGroup');
  }

  groups.add(<String, dynamic>{
    'name': privacyGroup,
    'type': 'select',
    'proxies': List<String>.from(landingTargets),
    'hidden': true,
  });
  raw['proxy-groups'] = groups;

  final rules = List<dynamic>.from(raw['rules'] as List? ?? const []);
  // WebRTC/STUN is UDP. Put the fail-closed rule before subscription DIRECT
  // rules so it cannot expose the physical mobile/Wi-Fi address. If SOCKS5 UDP
  // is disabled, reject UDP instead of allowing Mihomo to continue matching a
  // later DIRECT rule. When enabled, force every UDP flow through a residential
  // landing chain; DNS/53 is intercepted by TUN before normal routing.
  final udpRule = settings.udp
      ? 'NETWORK,udp,$privacyGroup'
      : 'NETWORK,udp,REJECT';

  raw['mode'] = 'rule';
  raw['rules'] = <dynamic>[
    udpRule,
    // Android Private DNS uses DoT/853 and cannot be hijacked as normal DNS by
    // Mihomo. Reject it in strict mode so it cannot silently bypass our resolver.
    'DST-PORT,853,REJECT',
    ...rules,
  ];

  _bindDnsToPrivacyGroup(raw, privacyGroup);
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
  int profileId, {
  bool enforceAndroidPrivacy = false,
}) {
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
    if (enforceAndroidPrivacy) {
      _applyAndroidTunnelPrivacy(raw);
    }
  }

  if (_hasDynamicProxySources(raw, groups)) {
    _applyDynamicSourceCompatibility(
      raw,
      proxies,
      groups,
      settings,
      profileId,
    );
    if (settings.dnsLeakProtection && enforceAndroidPrivacy) {
      final landingTargets = (raw['proxies'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => item['name']?.toString() ?? '')
          .where((name) => name.startsWith('__FLCLASH_CHAIN_EXIT_'))
          .toList();
      _applyAndroidPrivacyRouting(
        raw,
        settings,
        profileId,
        landingTargets,
      );
    }
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
  final landingTargets = <String>[];
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
    landingTargets.add(publicName);
  }

  if (chainIndex == 0) {
    throw StateError('当前配置没有可链式代理的节点');
  }

  raw['proxies'] = transformed;
  if (settings.dnsLeakProtection && enforceAndroidPrivacy) {
    _applyAndroidPrivacyRouting(raw, settings, profileId, landingTargets);
  }
  return yaml.encode(raw);
}
