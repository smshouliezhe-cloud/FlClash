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
  bool _strict = true;
  String? _sourceProxy;

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
      _strict = settings.strict;
      _sourceProxy = settings.sourceProxy.isEmpty ? null : settings.sourceProxy;
      _serverController.text = settings.server;
      _portController.text = settings.port == 0 ? '' : settings.port.toString();
      _usernameController.text = settings.username;
      _passwordController.text = settings.password;
      _loading = false;
    });
  }

  List<String> _availableNodes() {
    final groupTypes = GroupType.values.map((item) => item.name).toSet();
    final names = <String>{};
    for (final group in ref.read(groupsProvider)) {
      for (final proxy in group.all) {
        if (!groupTypes.contains(proxy.type) &&
            proxy.name != 'DIRECT' &&
            proxy.name != 'REJECT') {
          names.add(proxy.name);
        }
      }
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
    if (_enabled && (_sourceProxy == null || _sourceProxy!.isEmpty)) {
      dialogs.showNotifier('请选择机场前置节点');
      return;
    }

    final settings = ChainProxySettings(
      enabled: _enabled,
      sourceProxy: _sourceProxy ?? '',
      server: _serverController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 0,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      udp: _udp,
      strict: _strict,
    );

    setState(() => _saving = true);
    try {
      await preferences.saveChainProxySettings(profileId, settings);
      final applied = await ref
          .read(setupActionProvider.notifier)
          .applyProfile(force: true);
      if (!applied) {
        dialogs.showNotifier('链式代理配置校验或应用失败，请检查节点和 SOCKS5 参数');
        return;
      }
      dialogs.showNotifier(_enabled ? '链式代理已启用并应用' : '链式代理已关闭');
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
    final nodes = _availableNodes();
    if (_sourceProxy != null && !nodes.contains(_sourceProxy)) {
      nodes.insert(0, _sourceProxy!);
    }

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
              subtitle: const Text('手机 → 机场前置节点 → 住宅 SOCKS5 → Internet'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _sourceProxy,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '机场前置节点',
              ),
              items: nodes
                  .map(
                    (name) => DropdownMenuItem<String>(
                      value: name,
                      child: Text(name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: _enabled
                  ? (value) => setState(() => _sourceProxy = value)
                  : null,
              validator: (_) => _enabled && (_sourceProxy?.isEmpty ?? true)
                  ? '请选择机场前置节点'
                  : null,
            ),
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
              subtitle: const Text('开启后允许支持 UDP 的应用通过住宅 SOCKS5'),
              value: _udp,
              onChanged: _enabled ? (value) => setState(() => _udp = value) : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('严格模式（推荐）'),
              subtitle: const Text('强制 MATCH 走住宅出口，避免 SOCKS5 失效时退回机场直出'),
              value: _strict,
              onChanged: _enabled
                  ? (value) => setState(() => _strict = value)
                  : null,
            ),
            const SizedBox(height: 12),
            const Text(
              '启用后不会修改机场订阅。订阅刷新后仍保留本页设置；如果所选机场节点被删除或改名，配置会直接应用失败，不会静默绕过住宅出口。',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
