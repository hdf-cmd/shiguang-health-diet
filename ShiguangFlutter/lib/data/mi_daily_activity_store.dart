// ShiguangFlutter/lib/data/mi_daily_activity_store.dart
// 手表每日活动缓存（非敏感）：date → {steps, distanceM, activeKcal}。
// 数据来自小米云 get_fitness_data_by_time（steps/calories 分钟切片聚合）。
// 用途：每日消耗（TDEE = BMR + 手表活动热量）、实际缺口、预计时间的唯一
// 手表数据源；不写入运动记录（否则与 TDEE 双算）。
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mi_cloud_client.dart' show MiDailyActivity;

const miDailyActivityPrefKey = 'sg_mi_daily_activity';
const miLastSyncPrefKey = 'sg_mi_last_sync';
const miDailyActivityMaxDays = 30;

class MiDailyActivityStore {
  MiDailyActivityStore({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  Future<Map<String, MiDailyActivity>> load() async {
    final p = await _prefs();
    final raw = p.getString(miDailyActivityPrefKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const {};
      final out = <String, MiDailyActivity>{};
      for (final e in json.entries) {
        final v = e.value;
        if (v is! Map) continue;
        out['${e.key}'] = MiDailyActivity(
          date: '${e.key}',
          steps: (v['s'] as num?)?.toInt() ?? 0,
          distanceM: (v['d'] as num?)?.toDouble() ?? 0,
          activeKcal: (v['k'] as num?)?.toDouble() ?? 0,
        );
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// 合并写入并裁剪到最近 [miDailyActivityMaxDays] 个日期。
  Future<void> saveAll(Iterable<MiDailyActivity> days) async {
    final current = Map<String, MiDailyActivity>.of(await load());
    for (final d in days) {
      current[d.date] = d;
    }
    final keys = current.keys.toList()..sort();
    final kept = keys.length > miDailyActivityMaxDays
        ? keys.sublist(keys.length - miDailyActivityMaxDays)
        : keys;
    final encoded = <String, Object>{
      for (final k in kept)
        k: {
          's': current[k]!.steps,
          'd': current[k]!.distanceM,
          'k': current[k]!.activeKcal,
        },
    };
    final p = await _prefs();
    await p.setString(miDailyActivityPrefKey, jsonEncode(encoded));
  }

  Future<void> clear() async {
    final p = await _prefs();
    await p.remove(miDailyActivityPrefKey);
  }

  /// 上次成功同步日期（YYYY-MM-DD）：用于动态拉取窗口（断更天数回补）。
  Future<String?> loadLastSync() async {
    final p = await _prefs();
    return p.getString(miLastSyncPrefKey);
  }

  Future<void> saveLastSync(String date) async {
    final p = await _prefs();
    await p.setString(miLastSyncPrefKey, date);
  }
}

final miDailyActivityStoreProvider =
    Provider<MiDailyActivityStore>((ref) => MiDailyActivityStore());

/// 内存视图：同步完成后 invalidate 触发重算（首页额度/代谢卡/预计时间）。
final miDailyActivityProvider =
    FutureProvider<Map<String, MiDailyActivity>>((ref) async {
  return ref.read(miDailyActivityStoreProvider).load();
});
