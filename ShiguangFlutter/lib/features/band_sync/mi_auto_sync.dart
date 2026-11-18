// ShiguangFlutter/lib/features/band_sync/mi_auto_sync.dart
// 「打开 App 自动同步」接线：登录态为 authed 时静默跑一次；回前台距上次
// 成功超过 10 分钟再跑。失败静默（不打扰），成功刷新相关缓存。
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/auth_state.dart' show AuthStatus, authStateProvider;
import '../../data/mi_daily_activity_store.dart' show miDailyActivityProvider;
import '../exercise/exercise_controller.dart' show exercisesProvider;
import '../profile/profile_providers.dart'
    show actualDeficitProvider, profileProvider;
import 'mi_sync_service.dart' show miSyncServiceProvider;

class MiAutoSync with WidgetsBindingObserver {
  MiAutoSync(this._container);

  final ProviderContainer _container;
  static const _minInterval = Duration(minutes: 10);
  ProviderSubscription<AuthStatus>? _authSub;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    // bootstrap 是异步的：监听登录态进入 authed 时补跑一次（冷启动竞态）。
    _authSub = _container.listen<AuthStatus>(authStateProvider, (prev, next) {
      if (next == AuthStatus.authed && prev != AuthStatus.authed) {
        unawaited(_run(force: true));
      }
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_run(force: true)));
  }

  void dispose() {
    _authSub?.close();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_run());
  }

  Future<void> _run({bool force = false}) async {
    if (_container.read(authStateProvider) != AuthStatus.authed) return;
    final service = _container.read(miSyncServiceProvider);
    final last = service.lastOkAt;
    if (!force && last != null && DateTime.now().difference(last) < _minInterval) {
      return;
    }
    final profile = _container.read(profileProvider).maybeWhen(
          data: (v) => v,
          orElse: () => null,
        );
    num? weight;
    final body = profile?['body'];
    if (body is Map) weight = body['weightKg'] as num?;
    final outcome = await service.run(weightKg: weight);
    if (outcome == null) return;
    if (outcome.imported > 0 || outcome.ok) {
      _container.invalidate(miDailyActivityProvider);
      for (final d in outcome.dates) {
        _container.invalidate(exercisesProvider(d));
      }
      _container.invalidate(actualDeficitProvider);
    }
  }
}

MiAutoSync? _instance;

/// main() 调用一次；容器生命周期与 App 一致。
void startMiAutoSync(ProviderContainer container) {
  _instance ??= MiAutoSync(container)..start();
}
