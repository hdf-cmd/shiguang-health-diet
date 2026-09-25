// ShiguangFlutter/test/domain/exercise_test.dart
// 逐条移植自 tests/logic.test.js #6 与 tests/nutrition.test.js exerciseKcalOf 3 条。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/constants.dart';
import 'package:shiguang_flutter/domain/exercise.dart';

void main() {
  final run = exerciseLib.firstWhere((l) => l.key == 'run');
  final swim = exerciseLib.firstWhere((l) => l.key == 'swim');

  test('exerciseKcalOf: 距离型与时长型公式（logic.test.js #6）', () {
    expect(exerciseKcalOf(run, 5, 55), 285); // 1.036*55*5
    expect(exerciseKcalOf(swim, 30, 55), 231); // 8*3.5*55/200*30
    expect(exerciseKcalOf(run, 5, null), 285); // 缺省体重 55
  });

  test('exerciseKcalOf: 距离型 = 系数 × 体重 × 距离', () {
    expect(exerciseKcalOf(run, 5, 60), (run.perKgKm! * 60 * 5).round());
    expect(exerciseKcalOf(run, 0, 60), 0); // 零距离 → 0
  });

  test('exerciseKcalOf: 时长型 = MET × 3.5 × 体重 ÷ 200 × 分钟', () {
    expect(exerciseKcalOf(swim, 30, 60), (swim.met! * 3.5 * 60 / 200 * 30).round());
    expect(exerciseKcalOf(swim, 0, 60), 0);
  });

  test('exerciseKcalOf: 体重缺省或为 0 时回退 55kg', () {
    expect(exerciseKcalOf(run, 5, null), exerciseKcalOf(run, 5, 55));
    expect(exerciseKcalOf(run, 5, 0), exerciseKcalOf(run, 5, 55));
  });
}
