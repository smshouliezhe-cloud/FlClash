import 'package:fl_clash/common/yaml.dart';
import 'package:fl_clash/models/windows_proxy_chain.dart';
import 'package:yaml/yaml.dart';

Object? _normalizeWindowsChainYaml(Object? value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _normalizeWindowsChainYaml(entry.value),
    };
  }
  if (value is YamlList) {
    return value.map(_normalizeWindowsChainYaml).toList();
  }
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _normalizeWindowsChainYaml(entry.value),
    };
  }
  if (value is List) {
    return value.map(_normalizeWindowsChainYaml).toList();
  }
  return value;
}

String applyWindowsProxyChainYaml(
  String sourceYaml,
  WindowsProxyChainSettings settings,
) {
  if (!settings.enabled) return sourceYaml;
  if (!settings.isComplete) {
    throw StateError('Windows 链式代理至少需要两个不同节点和一个目标代理组');
  }

  final parsed = loadYaml(sourceYaml);
  final normalized = _normalizeWindowsChainYaml(parsed);
  if (normalized is! Map<String, dynamic>) {
    throw StateError('无法解析当前代理配置');
  }

  final raw = Map<String, dynamic>.from(normalized);
  final proxies = List<dynamic>.from(raw['proxies'] as List? ?? const []);
  final proxyIndex = <String, int>{};

  for (var i = 0; i < proxies.length; i++) {
    final item = proxies[i];
    if (item is! Map) continue;
    final name = item['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) proxyIndex[name] = i;
  }

  for (final node in settings.nodes) {
    if (!proxyIndex.containsKey(node)) {
      throw StateError('链式代理节点已不存在：$node');
    }
  }

  final groups = List<dynamic>.from(raw['proxy-groups'] as List? ?? const []);
  final groupNames = <String>{
    for (final item in groups)
      if (item is Map && item['name'] != null) item['name'].toString(),
  };
  if (settings.targetGroup != 'GLOBAL' &&
      !groupNames.contains(settings.targetGroup)) {
    throw StateError('链式代理目标组已不存在：${settings.targetGroup}');
  }

  final transformed = proxies.map((item) {
    if (item is Map) return Map<String, dynamic>.from(item);
    return item;
  }).toList();

  // Clash Verge-style runtime chain semantics:
  // [A, B, C] => B.dialer-proxy=A, C.dialer-proxy=B, and the target group
  // selects C. This function deliberately changes only the generated runtime
  // YAML. It never writes subscription/profile source files or database rows.
  for (var i = 1; i < settings.nodes.length; i++) {
    final nodeName = settings.nodes[i];
    final previousName = settings.nodes[i - 1];
    final index = proxyIndex[nodeName]!;
    final proxy = Map<String, dynamic>.from(transformed[index] as Map);

    // Do not destroy a chain authored by the subscription itself. Clash Verge
    // clears every dialer-proxy in runtime; this implementation is stricter so
    // our feature cannot silently overwrite source-defined routing semantics.
    final existingDialer = proxy['dialer-proxy']?.toString().trim();
    if (existingDialer != null &&
        existingDialer.isNotEmpty &&
        existingDialer != previousName) {
      throw StateError('节点 $nodeName 已自带 dialer-proxy：$existingDialer');
    }

    proxy['dialer-proxy'] = previousName;
    transformed[index] = proxy;
  }

  raw['proxies'] = transformed;
  return yaml.encode(raw);
}
