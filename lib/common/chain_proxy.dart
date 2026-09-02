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

String _rewriteRuleTarget(
  String rule,
  String sourceGroup,
  String outboundName,
) {
  final noResolveSuffix = ',$sourceGroup,no-resolve';
  if (rule.endsWith(noResolveSuffix)) {
    return '${rule.substring(0, rule.length - noResolveSuffix.length)},$outboundName,no-resolve';
  }

  final targetSuffix = ',$sourceGroup';
  if (rule.endsWith(targetSuffix)) {
    return '${rule.substring(0, rule.length - targetSuffix.length)},$outboundName';
  }

  return rule;
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
    // The residential SOCKS5 is always reached through the currently selected
    // node of the airport group. Switching the group selection therefore
    // changes the first hop without changing chain settings.
    'dialer-proxy': sourceGroup,
    if (settings.username.trim().isNotEmpty)
      'username': settings.username.trim(),
    if (settings.password.isNotEmpty) 'password': settings.password,
  };

  raw['proxies'] = [...proxies, outbound];

  final originalRules = List<dynamic>.from(
    raw['rules'] as List? ?? const <dynamic>[],
  );
  if (originalRules.isEmpty) {
    throw StateError('当前配置没有可跟随的规则');
  }

  var replacedCount = 0;
  final rules = originalRules.map((item) {
    if (item is! String) return item;
    final rewritten = _rewriteRuleTarget(item, sourceGroup, outboundName);
    if (rewritten != item) replacedCount++;
    return rewritten;
  }).toList();

  if (replacedCount == 0) {
    throw StateError('当前规则未引用机场代理组：$sourceGroup');
  }

  // Rule-follow mode: keep the subscription's routing policy intact. Only
  // rules whose target is the selected airport group are redirected to the
  // residential chained outbound. DIRECT/REJECT and every unrelated rule are
  // preserved exactly as authored by the subscription.
  raw['mode'] = 'rule';
  raw['rules'] = rules;

  return yaml.encode(raw);
}
