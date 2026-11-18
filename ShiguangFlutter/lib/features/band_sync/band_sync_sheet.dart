// ShiguangFlutter/lib/features/band_sync/band_sync_sheet.dart
// 「手环数据同步」弹层：账号绑定 + 手动触发一次同步。
// 同步动作与自动同步共用 MiSyncService：
//   - 每日活动 → 本地缓存（驱动 TDEE/额度/预计时间），每次同步自动更新
//   - 单次运动 → 去重后自动导入站内记录（无需再点「导入」）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/mi_daily_activity_store.dart' show miDailyActivityProvider;
import '../common/sheet.dart' show showShiguangSheet;
import '../exercise/exercise_controller.dart' show exercisesProvider;
import '../profile/profile_providers.dart'
    show actualDeficitProvider, profileProvider;
import 'mi_credentials_store.dart'
    show MiCredentials, miCredentialStoreProvider;
import 'mi_sync_service.dart' show miSyncServiceProvider;

const bandUserKey = Key('band-user');
const bandPassKey = Key('band-pass');
const bandSyncKey = Key('band-sync');

Future<void> openBandSyncSheet(BuildContext context, WidgetRef ref) {
  return showShiguangSheet<void>(
    context,
    title: '手环数据同步',
    child: const _BandSyncSheet(),
  );
}

class _BandSyncSheet extends ConsumerStatefulWidget {
  const _BandSyncSheet();

  @override
  ConsumerState<_BandSyncSheet> createState() => _BandSyncSheetState();
}

class _BandSyncSheetState extends ConsumerState<_BandSyncSheet> {
  final _user = TextEditingController();
  final _pass = TextEditingController();

  bool _loadingCreds = true;
  bool _busy = false;
  MiCredentials? _creds;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final creds = await ref.read(miCredentialStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _creds = creds;
      _loadingCreds = false;
    });
  }

  Future<void> _sync() async {
    if (_busy) return;
    if (_creds == null) {
      final user = _user.text.trim();
      final pass = _pass.text.trim();
      if (user.isEmpty || pass.isEmpty) {
        setState(() => _error = '请填写 userId 和 passToken');
        return;
      }
      final creds = MiCredentials(userId: user, passToken: pass);
      await ref.read(miCredentialStoreProvider).save(creds);
      if (!mounted) return;
      _creds = creds;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    final outcome = await ref.read(miSyncServiceProvider).run(
          weightKg: _weightKg(),
        );
    if (!mounted) return;
    if (outcome == null) {
      setState(() {
        _busy = false;
        _error = '未绑定小米账号';
      });
      return;
    }
    ref.invalidate(miDailyActivityProvider);
    for (final d in outcome.dates) {
      ref.invalidate(exercisesProvider(d));
    }
    ref.invalidate(actualDeficitProvider);
    setState(() {
      _busy = false;
      if (outcome.error != null) {
        _error = outcome.imported > 0
            ? '已导入 ${outcome.imported} 条后中断：${outcome.error}'
            : '同步失败：${outcome.error}';
      } else {
        _message = outcome.imported > 0
            ? '已同步：自动导入 ${outcome.imported} 条运动，跳过 ${outcome.skipped} 条；每日活动已更新'
            : '已同步：每日活动已更新，没有新运动记录（跳过 ${outcome.skipped} 条）';
      }
    });
  }

  num? _weightKg() {
    final profile = ref.read(profileProvider).maybeWhen(
          data: (v) => v,
          orElse: () => null,
        );
    final body = profile?['body'];
    if (body is Map) {
      final w = body['weightKg'];
      if (w is num) return w;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingCreds) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Tokens.sp4),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Tokens.sp5, Tokens.sp2, Tokens.sp5, Tokens.sp4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '同步手表每日活动与单次运动。每日消耗/额度/预计时间按手表全天活动实算，'
            '运动记录自动导入、不重复抵扣。官方 App 照常连接手环，不受影响。',
            style: TextStyle(
                fontSize: Tokens.textSm, color: Tokens.ink2, height: 1.5),
          ),
          const SizedBox(height: Tokens.sp3),
          if (_creds == null) ...[
            TextField(
              key: bandUserKey,
              controller: _user,
              decoration: const InputDecoration(
                labelText: '小米 userId',
                helperText: '浏览器登录 account.xiaomi.com 后，从 cookies 复制',
              ),
            ),
            const SizedBox(height: Tokens.sp2),
            TextField(
              key: bandPassKey,
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: '小米 passToken'),
            ),
            const SizedBox(height: Tokens.sp3),
          ] else
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已绑定：${_mask(_creds!.userId)}',
                    style: const TextStyle(
                        fontSize: Tokens.textSm, color: Tokens.ink2),
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _creds = null;
                            _user.clear();
                            _pass.clear();
                          }),
                  child: const Text('换账号'),
                ),
              ],
            ),
          FilledButton(
            key: bandSyncKey,
            onPressed: _busy ? null : _sync,
            child: Text(_busy
                ? '同步中…'
                : (_creds == null ? '绑定并同步' : '同步最近数据')),
          ),
          if (_message != null) ...[
            const SizedBox(height: Tokens.sp2),
            Text(_message!,
                style: const TextStyle(
                    fontSize: Tokens.textSm, color: Tokens.ink2)),
          ],
          if (_error != null) ...[
            const SizedBox(height: Tokens.sp2),
            Text(_error!,
                style: const TextStyle(
                    fontSize: Tokens.textSm, color: Tokens.danger)),
          ],
        ],
      ),
    );
  }

  static String _mask(String userId) {
    if (userId.length <= 4) return '****';
    return '${userId.substring(0, 2)}****${userId.substring(userId.length - 2)}';
  }
}
