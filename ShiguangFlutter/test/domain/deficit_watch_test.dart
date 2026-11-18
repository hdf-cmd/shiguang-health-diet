// ShiguangFlutter/test/domain/deficit_watch_test.dart
// 智能缺口：手表日 TDEE = BMR+活动且不再叠加运动；无手表日沿用旧口径。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/deficit.dart';

void main() {
  test('手表日：TDEE=BMR+活动，运动不二次计入', () {
    final rows = [
      {'date': '2026-11-16', 'intake': 1500, 'exKcal': 407},
    ];
    final r = avgDeficitFromRowsSmart(
      2443, // 旧口径 tdee（不应采用）
      1777, // bmr
      {'2026-11-16': 861},
      rows,
      1,
    );
    expect(r, isNotNull);
    // 1777 + 861 - 1500 = 1138，而非 2443+407-1500
    expect(r!['avgDeficit'], 1138);
    expect(r['activeDays'], 1);
  });

  test('无手表日：回落 tdee + exKcal（旧口径不变）', () {
    final rows = [
      {'date': '2026-11-10', 'intake': 1500, 'exKcal': 300},
    ];
    final r = avgDeficitFromRowsSmart(2443, 1777, const {}, rows, 1);
    expect(r!['avgDeficit'], 2443 + 300 - 1500);
    expect(r.containsKey('activeDays'), false);
  });

  test('混合日期：各自按对应口径，均值正确', () {
    final rows = [
      {'date': '2026-11-16', 'intake': 1500, 'exKcal': 407}, // 手表 861
      {'date': '2026-11-10', 'intake': 1500, 'exKcal': 300}, // 无手表
    ];
    final r = avgDeficitFromRowsSmart(
        2443, 1777, {'2026-11-16': 861}, rows);
    // (1138 + 1243) / 2 = 1190.5 → jsRound 1191
    expect(r!['avgDeficit'], 1191);
    expect(r['days'], 2);
    expect(r['activeDays'], 1);
  });

  test('不足 2 天 → null（沿用预设缺口）', () {
    final r = avgDeficitFromRowsSmart(
        2443, 1777, {'2026-11-16': 861}, [
      {'date': '2026-11-16', 'intake': 1500, 'exKcal': 0},
    ]);
    expect(r, isNull);
  });
}
