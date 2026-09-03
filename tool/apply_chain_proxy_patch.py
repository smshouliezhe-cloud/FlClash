from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f'patch anchor not found in {path}: {old[:120]!r}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


# Export manually-written chain models and runtime YAML overlays. Android and
# Windows intentionally use separate settings so the two implementations cannot
# accidentally overwrite each other's persisted state.
patch(
    'lib/models/models.dart',
    "export 'clash_config.dart';\n",
    "export 'clash_config.dart';\nexport 'chain_proxy.dart';\nexport 'windows_proxy_chain.dart';\n",
)
patch(
    'lib/common/common.dart',
    "export 'changelog.dart';\n",
    "export 'changelog.dart';\nexport 'chain_proxy.dart';\nexport 'windows_proxy_chain.dart';\n",
)

# Persist chain settings in SharedPreferences only. Neither implementation gets
# a profile file path, subscription URL, profile database handle or delete API.
# This is deliberately isolated from Clash Verge's profile cleanup/update code.
patch(
    'lib/common/preferences.dart',
    "  Future<void> clearPreferences() async {\n",
    """  Future<ChainProxySettings> getChainProxySettings(int profileId) async {
    try {
      final sharedPreferencesIns = await sharedPreferencesCompleter.future;
      final raw = sharedPreferencesIns?.getString('chain_proxy_$profileId');
      if (raw == null || raw.isEmpty) return const ChainProxySettings();
      final decoded = json.decode(raw);
      if (decoded is! Map) return const ChainProxySettings();
      return ChainProxySettings.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } catch (e) {
      commonPrint.log(
        'getChainProxySettings error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return const ChainProxySettings();
    }
  }

  Future<bool> saveChainProxySettings(
    int profileId,
    ChainProxySettings settings,
  ) async {
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    return await sharedPreferencesIns?.setString(
          'chain_proxy_$profileId',
          json.encode(settings.toJson()),
        ) ??
        false;
  }

  Future<WindowsProxyChainSettings> getWindowsProxyChainSettings(
    int profileId,
  ) async {
    try {
      final sharedPreferencesIns = await sharedPreferencesCompleter.future;
      final raw = sharedPreferencesIns?.getString(
        'windows_proxy_chain_$profileId',
      );
      if (raw == null || raw.isEmpty) {
        return const WindowsProxyChainSettings();
      }
      final decoded = json.decode(raw);
      if (decoded is! Map) return const WindowsProxyChainSettings();
      return WindowsProxyChainSettings.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } catch (e) {
      commonPrint.log(
        'getWindowsProxyChainSettings error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return const WindowsProxyChainSettings();
    }
  }

  Future<bool> saveWindowsProxyChainSettings(
    int profileId,
    WindowsProxyChainSettings settings,
  ) async {
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    return await sharedPreferencesIns?.setString(
          'windows_proxy_chain_$profileId',
          json.encode(settings.toJson()),
        ) ??
        false;
  }

  Future<void> clearPreferences() async {
""",
)

# The normal FlClash profile pipeline remains authoritative. Chain features are
# applied only to the final generated runtime YAML. Source subscriptions and
# profile database rows are never rewritten by this feature.
patch(
    'lib/providers/actions/setup.dart',
    "    final res = makeRealProfileTask(\n",
    "    var res = await makeRealProfileTask(\n",
)
patch(
    'lib/providers/actions/setup.dart',
    """    );
    return res;
  }

  Future<String> getProfileWithId""",
    """    );
    if (system.isWindows) {
      final windowsChainSettings = await preferences
          .getWindowsProxyChainSettings(profileId);
      if (windowsChainSettings.enabled) {
        final chainedYaml = applyWindowsProxyChainYaml(
          res.yaml,
          windowsChainSettings,
        );
        res = (yaml: chainedYaml, md5: chainedYaml.toMd5());
      }
    } else if (system.isAndroid) {
      final chainSettings = await preferences.getChainProxySettings(profileId);
      if (chainSettings.enabled) {
        final chainedYaml = applyChainProxyYaml(
          res.yaml,
          chainSettings,
          profileId,
        );
        res = (yaml: chainedYaml, md5: chainedYaml.toMd5());
      }
    }
    return res;
  }

  Future<String> getProfileWithId""",
)

# Add platform-specific chain configuration entries to the existing proxies
# page. Android keeps the NekoBox-style landing proxy. Windows uses the ordered
# Clash Verge-style runtime chain UI.
patch(
    'lib/views/proxies/proxies.dart',
    "import 'package:fl_clash/views/proxies/list.dart';\n",
    "import 'package:fl_clash/views/proxies/chain_proxy.dart';\nimport 'package:fl_clash/views/proxies/list.dart';\nimport 'package:fl_clash/views/proxies/windows_proxy_chain.dart';\n",
)
patch(
    'lib/views/proxies/proxies.dart',
    """            if (_hasProviders)
              CommonPopupMenuItem(""",
    """            if (system.isWindows)
              CommonPopupMenuItem(
                icon: Icons.account_tree_outlined,
                label: '链式代理',
                onPressed: () {
                  showExtend(
                    context,
                    builder: (_) => const WindowsProxyChainView(),
                  );
                },
              )
            else if (system.isAndroid)
              CommonPopupMenuItem(
                icon: Icons.account_tree_outlined,
                label: '链式代理',
                onPressed: () {
                  showExtend(
                    context,
                    builder: (_) => const ChainProxyView(),
                  );
                },
              ),
            if (_hasProviders)
              CommonPopupMenuItem(""",
)

# yaml is used at runtime by both final-profile overlays, not just tests.
pubspec = ROOT / 'pubspec.yaml'
text = pubspec.read_text(encoding='utf-8')
if '\n  yaml: ^3.1.3\n' not in text.split('dev_dependencies:')[0]:
    text = text.replace(
        "  yaml_writer:\n",
        "  yaml: ^3.1.3\n  yaml_writer:\n",
        1,
    )
# Remove the former dev-only declaration, but only inside dev_dependencies.
head, marker, tail = text.partition('dev_dependencies:')
if marker:
    tail = tail.replace("\n  yaml: ^3.1.3", '', 1)
    text = head + marker + tail
pubspec.write_text(text, encoding='utf-8')

print('chain proxy patch applied')
