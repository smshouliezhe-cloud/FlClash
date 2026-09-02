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
  String? _sourceGroup;
  ChainProxyAppMode _appMode = ChainProxyAppMode.all;
  Set<String> _appPackages = <String>{};

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
    await ref.read(systemActionProvider.notifier).getPackages();
    if (!mounted) return;
    setState(() {
      _enabled = settings.enabled;
      _udp = settings.udp;
      _strict = settings.strict;
      _sourceGroup = settings.sourceGroup.isEmpty ? null : settings.sourceGroup;
      _appMode = settings.appMode;
      _appPackages = settings.appPackages.toSet();
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

  String _appModeLabel(ChainProxyAppMode mode) {
    return switch (mode) {
      ChainProxyAppMode.all => '全部应用',
      ChainProxyAppMode.selected => '仅选中应用',
    };
  }

  Future<void> _selectApps() async {
    final selected = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => ChainProxyAppSelectorView(
          initialSelected: _appPackages,
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _appPackages = selected);
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
    if (_enabled &&
        _appMode == ChainProxyAppMode.selected &&
        _appPackages.isEmpty) {
      dialogs.showNotifier('仅选中应用模式至少需要选择一个应用');
      return;
    }

    final packages = _appPackages.toList()..sort();
    final settings = ChainProxySettings(
      enabled: _enabled,
      sourceGroup: _sourceGroup ?? '',
      server: _serverController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 0,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      udp: _udp,
      strict: _strict,
      appMode: _appMode,
      appPackages: packages,
    );

    setState(() => _saving = true);
    try {
      await preferences.saveChainProxySettings(profileId, settings);
      final applied = await ref
          .read(setupActionProvider.notifier)
          .applyProfile(force: true);
      if (!applied) {
        dialogs.showNotifier('链式代理配置校验或应用失败，请检查代理组、应用范围和 SOCKS5 参数');
        return;
      }
      final scopeText = _appMode == ChainProxyAppMode.all
          ? '全部应用'
          : '${_appPackages.length} 个选中应用';
      dialogs.showNotifier(
        _enabled ? '链式代理已启用并应用：$scopeText' : '链式代理已关闭',
      );
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
              subtitle: const Text('手机 → 机场代理组当前节点 → 住宅 SOCKS5 → Internet'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _sourceGroup,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '机场代理组',
                helperText: '绑定代理组后，在代理页切换节点无需重新设置链式代理',
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
            DropdownButtonFormField<ChainProxyAppMode>(
              initialValue: _appMode,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '应用范围',
                helperText: '仅选中应用时，其他 App 继续使用原订阅规则，不经过住宅 SOCKS5',
              ),
              items: ChainProxyAppMode.values
                  .map(
                    (mode) => DropdownMenuItem<ChainProxyAppMode>(
                      value: mode,
                      child: Text(_appModeLabel(mode)),
                    ),
                  )
                  .toList(),
              onChanged: _enabled
                  ? (value) {
                      if (value == null) return;
                      setState(() => _appMode = value);
                    }
                  : null,
            ),
            if (_appMode == ChainProxyAppMode.selected) ...[
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: _enabled,
                leading: const Icon(Icons.apps_outlined),
                title: const Text('选择链式应用'),
                subtitle: Text(
                  _appPackages.isEmpty
                      ? '尚未选择应用'
                      : '已选择 ${_appPackages.length} 个应用',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _enabled ? _selectApps : null,
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
              subtitle: const Text('开启后允许支持 UDP 的应用通过住宅 SOCKS5'),
              value: _udp,
              onChanged: _enabled ? (value) => setState(() => _udp = value) : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('严格模式（推荐）'),
              subtitle: Text(
                _appMode == ChainProxyAppMode.all
                    ? '全部应用模式下强制 MATCH 走住宅出口，避免 SOCKS5 失效时退回机场直出'
                    : '选中应用直接绑定住宅出口；住宅 SOCKS5 失效时不会自动退回机场直出',
              ),
              value: _strict,
              onChanged: _enabled
                  ? (value) => setState(() => _strict = value)
                  : null,
            ),
            const SizedBox(height: 12),
            const Text(
              '启用后不会修改机场订阅。链式代理绑定的是机场代理组，不是某一个节点；你在 FlClash 代理页正常切换该组节点，前置机场会自动跟随。仅选中应用模式使用 Android 包名生成 PROCESS-NAME 规则，并放在订阅规则最前面；未选中的应用继续使用原订阅规则。订阅刷新后住宅 SOCKS5 和应用列表仍然保留。',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class ChainProxyAppSelectorView extends ConsumerStatefulWidget {
  final Set<String> initialSelected;

  const ChainProxyAppSelectorView({
    super.key,
    required this.initialSelected,
  });

  @override
  ConsumerState<ChainProxyAppSelectorView> createState() =>
      _ChainProxyAppSelectorViewState();
}

class _ChainProxyAppSelectorViewState
    extends ConsumerState<ChainProxyAppSelectorView> {
  late Set<String> _selected;
  bool _loading = true;
  bool _permissionGranted = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
    Future.microtask(_loadPackages);
  }

  Future<void> _loadPackages({bool force = false}) async {
    final action = ref.read(systemActionProvider.notifier);
    final packages = force
        ? await action.refreshPackages()
        : await action.getPackages();
    final granted =
        packages.isNotEmpty || await action.isInstalledAppsPermissionGranted();
    if (!mounted) return;
    setState(() {
      _permissionGranted = granted;
      _loading = false;
    });
  }

  Future<void> _requestPermission() async {
    final action = ref.read(systemActionProvider.notifier);
    final granted = await action.requestInstalledAppsPermission();
    if (!mounted) return;
    if (!granted) {
      dialogs.showNotifier('未获得已安装应用读取权限');
      return;
    }
    setState(() => _loading = true);
    await _loadPackages(force: true);
  }

  void _toggleVisible(List<Package> packages) {
    final names = packages.map((item) => item.packageName).toSet();
    setState(() {
      if (_selected.containsAll(names)) {
        _selected.removeAll(names);
      } else {
        _selected.addAll(names);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(packagesProvider).toList()
      ..sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
    final query = _query.trim().toLowerCase();
    final visiblePackages = query.isEmpty
        ? packages
        : packages
              .where(
                (item) =>
                    item.label.toLowerCase().contains(query) ||
                    item.packageName.toLowerCase().contains(query),
              )
              .toList();
    final allVisibleSelected =
        visiblePackages.isNotEmpty &&
        _selected.containsAll(
          visiblePackages.map((item) => item.packageName),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text('选择链式应用（${_selected.length}）'),
        actions: [
          IconButton(
            tooltip: allVisibleSelected ? '取消当前列表全选' : '当前列表全选',
            onPressed: visiblePackages.isEmpty
                ? null
                : () => _toggleVisible(visiblePackages),
            icon: Icon(
              allVisibleSelected ? Icons.deselect : Icons.select_all,
            ),
          ),
          IconButton(
            tooltip: '完成',
            onPressed: () => Navigator.of(context).pop(_selected),
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_permissionGranted && packages.isEmpty
          ? Center(
              child: FilledButton.icon(
                onPressed: _requestPermission,
                icon: const Icon(Icons.lock_open),
                label: const Text('授权读取已安装应用'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                      labelText: '搜索应用或包名',
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                Expanded(
                  child: visiblePackages.isEmpty
                      ? const Center(child: Text('没有匹配的应用'))
                      : ListView.builder(
                          itemCount: visiblePackages.length,
                          itemBuilder: (_, index) {
                            final package = visiblePackages[index];
                            final checked = _selected.contains(
                              package.packageName,
                            );
                            return CheckboxListTile(
                              value: checked,
                              title: Text(
                                package.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                package.packageName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onChanged: (_) {
                                setState(() {
                                  if (checked) {
                                    _selected.remove(package.packageName);
                                  } else {
                                    _selected.add(package.packageName);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
