import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WindowsProxyChainView extends ConsumerStatefulWidget {
  const WindowsProxyChainView({super.key});

  @override
  ConsumerState<WindowsProxyChainView> createState() =>
      _WindowsProxyChainViewState();
}

class _WindowsProxyChainViewState
    extends ConsumerState<WindowsProxyChainView> {
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  String _targetGroup = '';
  String? _candidate;
  List<String> _nodes = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final settings = await preferences.getWindowsProxyChainSettings(profileId);
    if (!mounted) return;
    final fallbackGroup = _defaultTargetGroup();
    setState(() {
      _enabled = settings.enabled;
      _nodes = settings.nodes.toList();
      _targetGroup = settings.targetGroup.isNotEmpty
          ? settings.targetGroup
          : fallbackGroup;
      _loading = false;
    });
  }

  String _defaultTargetGroup() {
    final mode = ref.read(patchClashConfigProvider).mode;
    if (mode == Mode.global) return GroupName.GLOBAL.name;
    final profileGroup = ref.read(currentProfileProvider)?.currentGroupName ?? '';
    if (profileGroup.isNotEmpty) return profileGroup;
    final groups = ref.read(groupsProvider);
    for (final group in groups) {
      if (group.name != GroupName.GLOBAL.name) return group.name;
    }
    return GroupName.GLOBAL.name;
  }

  List<String> _targetGroups(List<Group> groups, Mode mode) {
    if (mode == Mode.global) return [GroupName.GLOBAL.name];
    return groups
        .map((group) => group.name)
        .where((name) => name != GroupName.GLOBAL.name)
        .toSet()
        .toList(growable: false);
  }

  List<Proxy> _candidates(List<Group> groups, Mode mode) {
    final groupNames = groups.map((group) => group.name).toSet();
    final builtinNames = <String>{
      'DIRECT',
      'REJECT',
      'REJECT-DROP',
      'PASS',
      'COMPATIBLE',
    };
    final source = <Proxy>[];
    if (mode == Mode.global || _targetGroup == GroupName.GLOBAL.name) {
      for (final group in groups) {
        source.addAll(group.all);
      }
    } else {
      final group = groups.getGroup(_targetGroup);
      if (group != null) source.addAll(group.all);
    }

    final seen = <String>{};
    return source.where((proxy) {
      final name = proxy.name.trim();
      if (name.isEmpty ||
          groupNames.contains(name) ||
          builtinNames.contains(name.toUpperCase()) ||
          _nodes.contains(name)) {
        return false;
      }
      return seen.add(name);
    }).toList(growable: false);
  }

  Future<void> _connect() async {
    if (_saving) return;
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) {
      dialogs.showNotifier('请先选择一个配置');
      return;
    }
    if (_nodes.length < 2) {
      dialogs.showNotifier('链式代理至少需要两个节点');
      return;
    }
    if (_targetGroup.isEmpty) {
      dialogs.showNotifier('请选择目标代理组');
      return;
    }

    setState(() => _saving = true);
    try {
      final settings = WindowsProxyChainSettings(
        enabled: true,
        nodes: List.unmodifiable(_nodes),
        targetGroup: _targetGroup,
      );
      await preferences.saveWindowsProxyChainSettings(profileId, settings);
      final applied = await ref
          .read(setupActionProvider.notifier)
          .applyProfile(force: true);
      if (!applied) {
        throw StateError('运行时链式配置应用失败');
      }
      await ref.read(proxiesActionProvider.notifier).changeProxy(
        groupName: _targetGroup,
        proxyName: _nodes.last,
      );
      if (!mounted) return;
      setState(() => _enabled = true);
      dialogs.showNotifier('链式代理已连接：${_nodes.join(' → ')}');
    } catch (e) {
      // Disable the overlay again if validation failed. The source subscription
      // is untouched either way because only preferences and runtime YAML are
      // involved in this feature.
      await preferences.saveWindowsProxyChainSettings(
        profileId,
        WindowsProxyChainSettings(
          enabled: false,
          nodes: List.unmodifiable(_nodes),
          targetGroup: _targetGroup,
        ),
      );
      dialogs.showNotifier('链式代理连接失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _disconnect() async {
    if (_saving) return;
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) return;
    setState(() => _saving = true);
    try {
      await preferences.saveWindowsProxyChainSettings(
        profileId,
        WindowsProxyChainSettings(
          enabled: false,
          nodes: List.unmodifiable(_nodes),
          targetGroup: _targetGroup,
        ),
      );
      final applied = await ref
          .read(setupActionProvider.notifier)
          .applyProfile(force: true);
      if (!applied) throw StateError('恢复普通代理配置失败');
      if (!mounted) return;
      setState(() => _enabled = false);
      dialogs.showNotifier('链式代理已断开');
    } catch (e) {
      dialogs.showNotifier('断开链式代理失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final groups = ref.watch(groupsProvider);
    final mode = ref.watch(patchClashConfigProvider.select((state) => state.mode));
    final targetGroups = _targetGroups(groups, mode);
    if (!targetGroups.contains(_targetGroup) && targetGroups.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _targetGroup = targetGroups.first;
          _candidate = null;
        });
      });
    }
    final candidates = _candidates(groups, mode);

    return Scaffold(
      appBar: AppBar(title: const Text('Windows 链式代理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '参考 Clash Verge 的运行时链式代理：第一个节点为入口，最后一个节点为出口。只修改最终运行配置中的 dialer-proxy，不修改、覆盖或删除订阅文件。',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: targetGroups.contains(_targetGroup) ? _targetGroup : null,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '目标代理组',
            ),
            items: targetGroups
                .map(
                  (name) => DropdownMenuItem<String>(
                    value: name,
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _enabled || _saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _targetGroup = value;
                      _candidate = null;
                      _nodes = [];
                    });
                  },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: candidates.any((proxy) => proxy.name == _candidate)
                      ? _candidate
                      : null,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '添加节点',
                  ),
                  items: candidates
                      .map(
                        (proxy) => DropdownMenuItem<String>(
                          value: proxy.name,
                          child: Text(
                            '${proxy.name}  [${proxy.type}]',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _enabled || _saving
                      ? null
                      : (value) => setState(() => _candidate = value),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _enabled || _saving || _candidate == null
                    ? null
                    : () {
                        setState(() {
                          _nodes.add(_candidate!);
                          _candidate = null;
                        });
                      },
                icon: const Icon(Icons.add),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_nodes.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('尚未添加链式节点')),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _nodes.length,
              onReorder: _enabled || _saving
                  ? (_, _) {}
                  : (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _nodes.removeAt(oldIndex);
                        _nodes.insert(newIndex, item);
                      });
                    },
              itemBuilder: (context, index) {
                final node = _nodes[index];
                final role = index == 0
                    ? '入口'
                    : index == _nodes.length - 1 && _nodes.length > 1
                    ? '出口'
                    : '${index + 1}';
                return Card(
                  key: ValueKey('$node-$index'),
                  child: ListTile(
                    leading: Chip(label: Text(role)),
                    title: Text(node),
                    subtitle: index == 0
                        ? const Text('链路从此节点开始')
                        : Text('dialer-proxy: ${_nodes[index - 1]}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '移除',
                          onPressed: _enabled || _saving
                              ? null
                              : () => setState(() => _nodes.removeAt(index)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          enabled: !_enabled && !_saving,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : _enabled
                ? _disconnect
                : _connect,
            icon: Icon(_enabled ? Icons.link_off : Icons.link),
            label: Text(_enabled ? '断开链式代理' : '连接链式代理'),
          ),
          const SizedBox(height: 12),
          const Text(
            '安全边界：链式模块只保存节点名称、顺序和目标组。订阅 URL、Profile 数据库记录、订阅 YAML 文件、更新定时器和文件清理逻辑均不在此模块权限范围内。订阅刷新后若节点名称消失，链式应用会直接报错，不会删除或修复订阅。',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}
