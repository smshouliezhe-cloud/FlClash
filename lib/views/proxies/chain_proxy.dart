import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChainProxyView extends ConsumerStatefulWidget {
  const ChainProxyView({super.key});

  @override
  ConsumerState<ChainProxyView> createState() => _ChainProxyViewState();
}

class _ChainProxyViewState extends ConsumerState<ChainProxyView> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  bool _udp = true;
  String? _sourceGroup;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _serverController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final settings = await preferences.getChainProxySettings(profileId);
    if (!mounted) return;
    setState(() {
      _enabled = settings.enabled;
      _udp = settings.udp;
      _sourceGroup = settings.sourceGroup.isEmpty ? null : settings.sourceGroup;
      _serverController.text = settings.server;
      _portController.text = settings.port == 0 ? '' : settings.port.toString();
      _usernameController.text = settings.username;
      _passwordController.text = settings.password;
      _loading = false;
    });
  }

  List<String> _availableGroups() {
    final names = <String>{};
    for (final group in ref.read(groupsProvider)) {
      if (group.name == GroupName.GLOBAL.name || group.all.isEmpty) continue;
      names.add(group.name);
    }
    final values = names.toList()..sort();
    return values;
  }

  Future<void> _save() async {
    if (_saving) return;
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) {
      dialogs.showNotifier('请先选择一个配置');
      return;
    }
    if (_enabled && _formKey.currentState?.validate() != true) return;
    if (_enabled && (_sourceGroup == null || _sourceGroup!.isEmpty)) {
      dialogs.showNotifier('请选择机场代理组');
      return;
    }

    final settings = ChainProxySettings(
      enabled: _enabled,
      sourceGroup: _sourceGroup ?? '',
      server: _serverController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 0,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      udp: _udp,
      strict: false,
      appMode: ChainProxyAppMode.all,
      appPackages: const [],
    );

    setState(() => _saving = true);
    try {
      await preferences.saveChainProxySettings(profileId, settings);
      final applied = await ref
          .read(setupActionProvider.notifier)
          .applyProfile(force: true);
      if (!applied) {
        dialogs.showNotifier('链式代理应用失败，请确认订阅规则中使用了所选机场代理组');
        return;
      }
      dialogs.showNotifier(_enabled ? '链式代理已按原订阅规则启用' : '链式代理已关闭');
      if (mounted) context.safeNestedPop();
    } catch (e) {
      dialogs.showNotifier('链式代理应用失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final groups = _availableGroups();
    if (_sourceGroup != null && !groups.contains(_sourceGroup)) {
      groups.insert(0, _sourceGroup!);
    }
    final selectedMap = ref.watch(selectedMapProvider);
    final selectedNode = _sourceGroup == null ? null : selectedMap[_sourceGroup];

    return Scaffold(
      appBar: AppBar(
        title: const Text('链式代理'),
        actions: [
          IconButton(
            tooltip: '保存并应用',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用链式代理'),
              subtitle: const Text('原订阅规则 → 机场当前节点 → 住宅 SOCKS5'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _sourceGroup,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '机场代理组',
                helperText: '原规则中指向这个代理组的流量才进入住宅链式出口',
              ),
              items: groups
                  .map(
                    (name) => DropdownMenuItem<String>(
                      value: name,
                      child: Text(name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: _enabled
                  ? (value) => setState(() => _sourceGroup = value)
                  : null,
              validator: (_) => _enabled && (_sourceGroup?.isEmpty ?? true)
                  ? '请选择机场代理组'
                  : null,
            ),
            if (selectedNode != null && selectedNode.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '当前前置节点：$selectedNode',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _serverController,
              enabled: _enabled,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '住宅 SOCKS5 地址',
              ),
              validator: (value) => _enabled && (value?.trim().isEmpty ?? true)
                  ? '请输入 SOCKS5 地址'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _portController,
              enabled: _enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '端口',
              ),
              validator: (value) {
                if (!_enabled) return null;
                final port = int.tryParse(value ?? '');
                if (port == null || port < 1 || port > 65535) {
                  return '端口必须为 1-65535';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _usernameController,
              enabled: _enabled,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '用户名（可选）',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              enabled: _enabled,
              obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '密码（可选）',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('SOCKS5 UDP'),
              subtitle: const Text('开启后允许匹配代理规则的 UDP 流量通过住宅 SOCKS5'),
              value: _udp,
              onChanged: _enabled ? (value) => setState(() => _udp = value) : null,
            ),
            const SizedBox(height: 12),
            const Text(
              '链式代理现在完全跟随原订阅规则。原规则为 DIRECT 或 REJECT 的流量保持不变；只有原规则目标为所选机场代理组的流量会改走“机场当前节点 → 住宅 SOCKS5”。在代理页切换机场节点无需重新设置，订阅刷新后住宅 SOCKS5 设置仍会保留。',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
