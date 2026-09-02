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

  final sourceName = settings.sourceProxy.trim();
  if (!proxyNames.contains(sourceName) && !groupNames.contains(sourceName)) {
    throw StateError('前置节点不存在：$sourceName');
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
    'dialer-proxy': sourceName,
    if (settings.username.trim().isNotEmpty)
      'username': settings.username.trim(),
    if (settings.password.isNotEmpty) 'password': settings.password,
  };

  raw['proxies'] = [...proxies, outbound];

  if (settings.strict) {
    // Leak-proof mode: force the core into rule mode and route every unmatched
    // connection through the residential SOCKS5 outbound. Existing rule
    // routing is intentionally bypassed so no traffic silently exits via the
    // airport node alone.
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
