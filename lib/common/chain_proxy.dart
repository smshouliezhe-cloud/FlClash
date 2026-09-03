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

String chainProxyOutboundName(int profileId, int index) =>
    '__FLCLASH_CHAIN_EXIT_${profileId}_$index';

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
  final originalRules = List<dynamic>.from(
    raw['rules'] as List? ?? const <dynamic>[],
  );
  if (originalRules.isEmpty) {
    throw StateError('当前配置没有可跟随的规则');
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

  // Find every actual proxy/proxy-group target referenced by the subscription
  // rules. DIRECT/REJECT and other built-in actions are not in knownTargets,
  // so they remain completely untouched.
  final usedTargets = <String>{};
  for (final item in originalRules) {
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

  for (var i = 0; i < sortedTargets.length; i++) {
    final target = sortedTargets[i];
    final outboundName = chainProxyOutboundName(profileId, i);
    if (proxyNames.contains(outboundName) || groupNames.contains(outboundName)) {
      throw StateError('链式代理内部节点名称冲突：$outboundName');
    }
    targetOutbounds[target] = outboundName;
    outbounds.add(<String, dynamic>{
      'name': outboundName,
      'type': 'socks5',
      'server': settings.server.trim(),
      'port': settings.port,
      'udp': settings.udp,
      // The rule's original proxy target becomes the dialer for the shared
      // residential SOCKS5. Therefore the original selector/group keeps all
      // of its normal node switching, fallback and url-test behaviour while
      // the residential SOCKS5 remains the final public egress.
      'dialer-proxy': target,
      if (settings.username.trim().isNotEmpty)
        'username': settings.username.trim(),
      if (settings.password.isNotEmpty) 'password': settings.password,
    });
  }

  final rules = originalRules.map((item) {
    if (item is! String) return item;
    final target = _getRuleProxyTarget(item, knownTargets);
    if (target == null) return item;
    final outboundName = targetOutbounds[target];
    if (outboundName == null) return item;
    return _rewriteRuleProxyTarget(item, target, outboundName);
  }).toList();

  // True rule-follow mode: every rule that originally chose a real proxy or
  // proxy group now chooses a residential SOCKS5 outbound whose dialer is that
  // exact original target. DIRECT/REJECT rules and their ordering are kept.
  raw['mode'] = 'rule';
  raw['proxies'] = [...proxies, ...outbounds];
  raw['rules'] = rules;

  return yaml.encode(raw);
}
