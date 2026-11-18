// ShiguangFlutter/test/data/mi_daily_activity_store_test.dart
// 每日活动缓存：往返、裁剪、坏数据容错。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_flutter/data/mi_cloud_client.dart' show MiDailyActivity;
import 'package:shiguang_flutter/data/mi_daily_activity_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saveAll 往返一致', () async {
    final store = MiDailyActivityStore();
    await store.saveAll([
      const MiDailyActivity(date: '2026-11-17', steps: 18780, distanceM: 12500, activeKcal: 655),
    ]);
    final m = await store.load();
    expect(m['2026-11-17']!.steps, 18780);
    expect(m['2026-11-17']!.activeKcal, 655);
  });

  test('超过 30 天淘汰最老日期', () async {
    final store = MiDailyActivityStore();
    final days = List.generate(
        miDailyActivityMaxDays + 3,
        (i) => MiDailyActivity(
            date: '2026-10-${(i + 1).toString().padLeft(2, '0')}',
            steps: i,
            distanceM: 0,
            activeKcal: i.toDouble()));
    await store.saveAll(days);
    final m = await store.load();
    expect(m.length, miDailyActivityMaxDays);
    expect(m.containsKey('2026-10-01'), false);
    expect(m.containsKey('2026-10-33'), true);
  });

  test('坏数据返回空表', () async {
    SharedPreferences.setMockInitialValues(
        {miDailyActivityPrefKey: 'not-json'});
    final store = MiDailyActivityStore();
    expect(await store.load(), isEmpty);
  });
}
