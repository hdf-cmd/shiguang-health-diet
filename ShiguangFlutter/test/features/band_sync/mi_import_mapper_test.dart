// ShiguangFlutter/test/features/band_sync/mi_import_mapper_test.dart
// 小米云运动记录映射用例：正常/边界/失败三类。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/mi_cloud_client.dart';
import 'package:shiguang_flutter/features/band_sync/mi_import_mapper.dart';

MiWorkout workout({
  String id = 'w1',
  String type = 'outdoor_running',
  DateTime? start,
  DateTime? end,
  int minutes = 30,
  double? distanceM,
  double? kcal,
  int? avgHr,
}) {
  final s = start ?? DateTime(2026, 11, 18, 7, 30);
  return MiWorkout(
    workoutId: id,
    activityType: type,
    startAt: s,
    endAt: end ?? s.add(Duration(minutes: minutes)),
    durationMinutes: minutes,
    distanceM: distanceM,
    caloriesKcal: kcal,
    avgHeartRate: avgHr,
  );
}

void main() {
  group('正常映射', () {
    test('跑步：距离 km、卡路里优先取云端值', () {
      final r = mapMiWorkouts(
        workouts: [workout(distanceM: 2834, kcal: 190, avgHr: 153)],
        weightKg: 76,
      );
      expect(r.skipped, isEmpty);
      final c = r.candidates.single;
      expect(c.payload.keys.toSet(),
          {'date', 'key', 'name', 'emoji', 'amount', 'unit', 'kcal'});
      expect(c.payload['date'], '2026-11-18');
      expect(c.payload['key'], 'run');
      expect(c.payload['amount'], 2.83);
      expect(c.payload['unit'], 'km');
      expect(c.payload['kcal'], 190); // 云端实测值优先于公式
      expect(c.externalId, 'mi:w1');
      expect(c.sourceKcal, 190);
      expect(c.estimatedDistance, false);
    });

    test('游泳：时长型 + 云端卡路里', () {
      final r = mapMiWorkouts(
        workouts: [
          workout(type: 'pool_swimming', minutes: 40, kcal: 300),
        ],
        weightKg: 76,
      );
      final c = r.candidates.single;
      expect(c.payload['key'], 'swim');
      expect(c.payload['amount'], 40);
      expect(c.payload['unit'], 'min');
      expect(c.payload['kcal'], 300);
    });

    test('缺距离的距离型：按典型配速估算并打标', () {
      final r = mapMiWorkouts(
        workouts: [workout(type: 'outdoor_walking', minutes: 30)],
        weightKg: 60,
      );
      final c = r.candidates.single;
      expect(c.payload['amount'], 2.5); // 5km/h × 0.5h
      expect(c.estimatedDistance, true);
      // 无云端卡路里 → 公式：0.5 × 60 × 2.5 = 75
      expect(c.payload['kcal'], 75);
    });

    test('输出按开始时间升序', () {
      final r = mapMiWorkouts(
        workouts: [
          workout(
              id: 'late',
              type: 'yoga',
              start: DateTime(2026, 11, 18, 20)),
          workout(
              id: 'early',
              type: 'outdoor_walking',
              start: DateTime(2026, 11, 18, 8),
              distanceM: 2000),
        ],
        weightKg: 55,
      );
      expect(r.candidates.map((c) => c.externalId).toList(),
          ['mi:early', 'mi:late']);
    });

    test('空输入 → 空结果', () {
      final r = mapMiWorkouts(workouts: const [], weightKg: 55);
      expect(r.isEmpty, true);
      expect(r.skipped, isEmpty);
    });
  });

  group('边界与跳过', () {
    test('跳绳（次数型）→ unsupportedActivity，不猜次数', () {
      final r = mapMiWorkouts(
        workouts: [workout(type: 'rope_skipping', minutes: 1, kcal: 6)],
        weightKg: 76,
      );
      expect(r.candidates, isEmpty);
      expect(r.skipped.single.reason, MiSkipReason.unsupportedActivity);
    });

    test('未知类型 → unsupportedActivity', () {
      final r = mapMiWorkouts(
        workouts: [workout(type: 'sleep_walking')],
        weightKg: 55,
      );
      expect(r.skipped.single.reason, MiSkipReason.unsupportedActivity);
    });

    test('起止非法 → invalidRange', () {
      final s = DateTime(2026, 11, 18, 9);
      final r = mapMiWorkouts(
        workouts: [workout(start: s, end: s)],
        weightKg: 55,
      );
      expect(r.skipped.single.reason, MiSkipReason.invalidRange);
    });

    test('时长型 0 分钟 → tooShort', () {
      final s = DateTime(2026, 11, 18, 9);
      final r = mapMiWorkouts(
        workouts: [
          workout(
              type: 'yoga',
              minutes: 0,
              start: s,
              end: s.add(const Duration(seconds: 30))),
        ],
        weightKg: 55,
      );
      expect(r.skipped.single.reason, MiSkipReason.tooShort);
    });

    test('距离型 0 距离且 0 时长 → zeroAmount', () {
      final s = DateTime(2026, 11, 18, 9);
      final r = mapMiWorkouts(
        workouts: [workout(start: s, end: s.add(const Duration(seconds: 1)), minutes: 0)],
        weightKg: 55,
      );
      expect(r.skipped.single.reason, MiSkipReason.zeroAmount);
    });

    test('云端内容签名命中（老数据无 externalId）→ alreadyImported', () {
      final r = mapMiWorkouts(
        workouts: [workout(id: 'new', distanceM: 2834, kcal: 190)],
        weightKg: 76,
        importedSignatures: const {'2026-11-18|run|2.83|190'},
      );
      expect(r.candidates, isEmpty);
      expect(r.skipped.single.reason, MiSkipReason.alreadyImported);
    });

    test('已导入 externalId 命中 → alreadyImported', () {
      final r = mapMiWorkouts(
        workouts: [workout(id: 'done', distanceM: 3000)],
        weightKg: 55,
        importedIds: const {'mi:done'},
      );
      expect(r.candidates, isEmpty);
      expect(r.skipped.single.reason, MiSkipReason.alreadyImported);
    });

    test('同 id 重复 → duplicate', () {
      final r = mapMiWorkouts(
        workouts: [
          workout(id: 'same', distanceM: 3000),
          workout(id: 'same', distanceM: 3000),
        ],
        weightKg: 55,
      );
      expect(r.candidates, hasLength(1));
      expect(r.skipped.single.reason, MiSkipReason.duplicate);
    });

    test('同会话不同 id（多设备重复上报）→ 第二条 duplicate', () {
      final s = DateTime(2026, 11, 18, 7, 30);
      final r = mapMiWorkouts(
        workouts: [
          workout(id: 'a', start: s, distanceM: 3000),
          workout(id: 'b', start: s, distanceM: 3000),
        ],
        weightKg: 55,
      );
      expect(r.candidates, hasLength(1));
      expect(r.skipped.single.reason, MiSkipReason.duplicate);
    });
  });

  test('本地日期口径：跨零点运动按开始日归日', () {
    final r = mapMiWorkouts(
      workouts: [
        workout(
          start: DateTime(2026, 11, 18, 23, 40),
          end: DateTime(2026, 11, 19, 0, 20),
          minutes: 40,
          type: 'pool_swimming',
        ),
      ],
      weightKg: 60,
    );
    expect(r.candidates.single.payload['date'], '2026-11-18');
  });
}
