import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VpnManager extends ConsumerStatefulWidget {
  final Widget child;

  const VpnManager({super.key, required this.child});

  @override
  ConsumerState<VpnManager> createState() => _VpnContainerState();
}

class _VpnContainerState extends ConsumerState<VpnManager> {
  bool _enforcingChainLeakGuard = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      vpnStateProvider,
      (prev, next) {
        if (prev != next) {
          unawaited(_handleVpnState(next));
        }
      },
      fireImmediately: true,
    );
    ref.listenManual(currentProfileIdProvider, (prev, next) {
      if (prev != next) {
        unawaited(_enforceChainLeakGuard());
      }
    });
  }

  Future<void> _handleVpnState(VpnState state) async {
    if (_enforcingChainLeakGuard) return;
    final enforced = await _enforceChainLeakGuard();
    if (!enforced && mounted) {
      showTip(state);
    }
  }

  Future<bool> _enforceChainLeakGuard() async {
    if (!system.isAndroid || _enforcingChainLeakGuard) return false;
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) return false;

    _enforcingChainLeakGuard = true;
    try {
      final chainSettings = await preferences.getChainProxySettings(profileId);
      if (!mounted || !chainSettings.enabled) return false;

      final current = ref.read(vpnSettingProvider);
      final hardened = current.copyWith(
        enable: true,
        allowBypass: false,
        dnsHijacking: true,
      );
      if (current == hardened) return false;

      final setupAction = ref.read(setupActionProvider.notifier);
      final wasRunning = ref.read(isStartProvider);
      if (wasRunning) {
        await setupAction.setRunning(false);
      }

      ref.read(vpnSettingProvider.notifier).update((_) => hardened);

      if (wasRunning) {
        final restarted = await setupAction.setRunning(true);
        if (!restarted) {
          dialogs.showNotifier(
            '住宅链式代理需要 VPN/TUN 防泄露保护，但 VPN/TUN 重启失败',
            level: MessageLevel.error,
          );
          return true;
        }
      }

      dialogs.showNotifier(
        '住宅链式代理已开启：VPN/TUN、防绕过和 DNS 劫持已强制恢复',
        level: MessageLevel.warning,
      );
      return true;
    } finally {
      _enforcingChainLeakGuard = false;
    }
  }

  void showTip(VpnState state) {
    throttler.call(
      FunctionTag.vpnTip,
      () {
        if (!ref.read(isStartProvider) || state == globalState.lastVpnState) {
          return;
        }
        dialogs.showNotifier(
          currentAppLocalizations.vpnConfigChangeDetected,
          level: MessageLevel.warning,
          actionState: MessageActionState(
            actionText: currentAppLocalizations.restart,
            action: () async {
              final setupAction = ref.read(setupActionProvider.notifier);
              await setupAction.setRunning(false);
              await setupAction.setRunning(true);
            },
          ),
        );
      },
      duration: const Duration(seconds: 10),
      fire: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
