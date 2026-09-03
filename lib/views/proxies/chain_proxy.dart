import 'package:fl_clash/common/common.dart';
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
      _serverController.text = settings.server;
      _portController.text = settings.port == 0 ? '' : settings.port.toString();
      _usernameController.text = settings.username;
      _passwordController.text = settings.password;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) {
      dialogs.showNotifier('请先选择一个配置');
      return;
    }
    if (_enabled && _formKey.currentState?.validate() != true) return;

    final settings = ChainProxySettings(
      enabled: _enabled,
      server: _serverController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 0,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      udp: _udp,
    );

    setState(() => _saving = true);
    try {
      await preferences.saveChainProxySettings(profileId, settings);
      final applied = await ref
          .read(setupActionProvider.notifier)
          .applyProfile(force: true);
      if (!applied) {
        dialogs.showNotifier('链式代理应用失败，请检查当前配置和住宅 SOCKS5 参数');
        return;
      }
      dialogs.showNotifier(_enabled ? '住宅落地代理已应用到当前订阅' : '链式代理已关闭');
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
              title: const Text('启用住宅落地代理'),
              subtitle: const Text('机场当前节点 → 住宅 SOCKS5 → Internet'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
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
              subtitle: const Text('允许代理流量通过住宅 SOCKS5 使用 UDP'),
              value: _udp,
              onChanged: _enabled ? (value) => setState(() => _udp = value) : null,
            ),
            const SizedBox(height: 16),
            const Text(
              '实现方式参考 NekoBox 的落地代理模型。普通订阅不会改动原来的规则、地区组或总选择组；每个机场节点仍保留原名称和原选择位置，但实际连接会自动变成“机场节点 → 住宅 SOCKS5”。因此香港、日本、自动选择等多层代理组都可正常切换，DIRECT 和 REJECT 不受影响，也不需要单独指定某个机场组。动态 proxy-provider 配置会自动使用兼容模式。订阅刷新后住宅 SOCKS5 设置仍然保留。',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
