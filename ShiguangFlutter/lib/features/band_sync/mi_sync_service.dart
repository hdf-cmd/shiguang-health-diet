// ShiguangFlutter/lib/features/band_sync/mi_sync_service.dart
// 小米云同步服务：优先复用缓存的登录会话（避免每次登录轮换 passToken）；
// 会话失效才重新登录。窗口按距上次同步天数动态扩展（7-30 天），断更回补。
// 每日活动只进缓存（驱动 TDEE/额度/预计时间）；运动记录去重后自动导入。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mi_cloud_client.dart';
import '../../data/mi_daily_activity_store.dart'
    show MiDailyActivityStore, miDailyActivityStoreProvider;
import '../home/home_controller.dart' show healthApiProvider;
import 'mi_credentials_store.dart'
    show
        MiCredentialStore,
        MiCredentials,
        MiSessionStore,
        miCredentialStoreProvider,
        miSessionStoreProvider;
import 'mi_import_mapper.dart' show localDateOf, mapMiWorkouts;
import 'mi_import_store.dart' show MiImportStore, miImportStoreProvider;

class MiSyncOutcome {
  const MiSyncOutcome({
    required this.imported,
    required this.skipped,
    required this.dates,
    this.error,
  });

  final int imported;
  final int skipped;

  /// 本次实际写入的日期集合（供上层 invalidate exercisesProvider）。
  final Set<String> dates;
  final String? error;

  bool get ok => error == null;
}

class MiSyncService {
  MiSyncService({
    required this.credentials,
    required this.importStore,
    required this.dailyStore,
    required this.addExercise,
    this.sessionStore,
    MiCloudClient Function()? clientFactory,
  }) : clientFactory = clientFactory ?? (() => MiCloudClient(MiDioHttp()));

  final MiCredentialStore credentials;
  final MiImportStore importStore;
  final MiDailyActivityStore dailyStore;
  final MiSessionStore? sessionStore;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) addExercise;
  final MiCloudClient Function() clientFactory;

  bool _running = false;
  DateTime? _lastOkAt;
  DateTime? get lastOkAt => _lastOkAt;

  /// 执行一次同步。未绑定凭据返回 null（静默无操作）。
  Future<MiSyncOutcome?> run({required num? weightKg}) async {
    if (_running) return null;
    final creds = await credentials.load();
    if (creds == null) return null;
    _running = true;
    try {
      final client = clientFactory();
      // 1) 优先复用缓存的会话（不登录 → 不轮换 token）。
      final cached = await sessionStore?.load();
      if (cached != null && cached.userId == creds.userId) {
        try {
          return await _fetchAndImport(client, cached, weightKg);
        } on MiAuthException {
          await sessionStore?.clear(); // 会话过期：丢弃缓存，走重新登录
        }
      }
      // 2) 重新登录（轮换 token，两个存储都要更新）。
      final fresh = await client.login(creds.userId, creds.passToken);
      await credentials.save(
          MiCredentials(userId: fresh.userId, passToken: fresh.passToken));
      await sessionStore?.save(fresh);
      return await _fetchAndImport(client, fresh, weightKg);
    } on MiAuthException catch (e) {
      return MiSyncOutcome(
          imported: 0, skipped: 0, dates: const {}, error: '登录失效：${e.message}');
    } on MiApiException catch (e) {
      return MiSyncOutcome(
          imported: 0, skipped: 0, dates: const {}, error: '云端错误：${e.message}');
    } catch (_) {
      return const MiSyncOutcome(
          imported: 0, skipped: 0, dates: {}, error: '网络异常');
    } finally {
      _running = false;
    }
  }

  /// 拉取 + 导入。窗口 = max(7, 距上次同步天数 + 1)，上限 30 天。
  Future<MiSyncOutcome> _fetchAndImport(
      MiCloudClient client, MiSession session, num? weightKg) async {
    final now = DateTime.now();
    var days = 7;
    final last = await dailyStore.loadLastSync();
    final lastDate = last == null ? null : DateTime.tryParse(last);
    if (lastDate != null) {
      final gap = DateTime(now.year, now.month, now.day)
              .difference(DateTime(lastDate.year, lastDate.month, lastDate.day))
              .inDays +
          1;
      days = gap.clamp(7, 30);
    }
    final start = now.subtract(Duration(days: days - 1));

    try {
      final daily = await client.fetchDailyActivity(
          session: session, start: start, end: now);
      await dailyStore.saveAll(daily);
    } catch (_) {
      // 每日活动失败不阻断运动记录同步。
    }
    final workouts = await client.fetchWorkouts(
        session: session, start: start, end: now);
    final result = mapMiWorkouts(
      workouts: workouts,
      weightKg: weightKg,
      importedIds: await importStore.load(),
    );
    final done = <String>[];
    final dates = <String>{};
    String? error;
    for (final c in result.candidates) {
      try {
        final res = await addExercise(c.payload);
        if (res['ok'] == false) {
          error = '${res['message'] ?? '导入失败'}';
          break;
        }
        done.add(c.externalId);
        dates.add('${c.payload['date']}');
      } catch (_) {
        error = '网络异常';
        break;
      }
    }
    if (done.isNotEmpty) {
      try {
        await importStore.addAll(done);
      } catch (_) {
        // 账本失败不阻断：下次可能重复导入，但不丢数据。
      }
    }
    // 数据拉取完成即记录同步日（导入部分失败会在下次 7 天窗口内重试）。
    try {
      await dailyStore.saveLastSync(localDateOf(now));
    } catch (_) {}
    if (error == null) _lastOkAt = DateTime.now();
    return MiSyncOutcome(
        imported: done.length,
        skipped: result.skipped.length,
        dates: dates,
        error: error);
  }
}

final miSyncServiceProvider = Provider<MiSyncService>((ref) {
  return MiSyncService(
    credentials: ref.watch(miCredentialStoreProvider),
    importStore: ref.watch(miImportStoreProvider),
    dailyStore: ref.watch(miDailyActivityStoreProvider),
    sessionStore: ref.watch(miSessionStoreProvider),
    addExercise: ref.watch(healthApiProvider).addExercise,
  );
});
