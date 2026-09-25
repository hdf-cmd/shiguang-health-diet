// ShiguangFlutter/test/domain/exercise_test.dart
// 逐条移植自 tests/logic.test.js #6 与 tests/nutrition.test.js exerciseKcalOf 3 条。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/constants.dart';
import 'package:shiguang_flutter/domain/exercise.dart';

void main() {
  final run = exerciseLib.firstWhere((l) => l.key == 'run');
  final swim = exerciseLib.firstWhere((l) => l.key == 'swim');
  final pushup = exerciseLib.firstWhere((l) => l.key == 'pushup');
  final rope = exerciseLib.firstWhere((l) => l.key == 'rope');

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

  // ── 次数型（对齐 logic.test.js「次数型」「exerciseAmountLabel」「isRepRecord」）──
  test('exerciseKcalOf: 次数型 = 系数 × 体重 × 次数', () {
    expect(pushup.unit, 'rep');
    expect(rope.unit, 'rep');
    expect(exerciseKcalOf(pushup, 30, 70), 9); // 0.0045*70*30=9.45→9
    expect(exerciseKcalOf(pushup, 1, 70), 0);  // 0.315→0
    expect(exerciseKcalOf(rope, 1000, 70), 84);
    expect(exerciseKcalOf(rope, 500, 55), 33);
  });

  test('exerciseAmountLabel: 三型各自标题与单位', () {
    expect(exerciseAmountLabel(run), const ('距离', 'km'));
    expect(exerciseAmountLabel(swim), const ('时长', '分钟'));
    expect(exerciseAmountLabel(pushup), const ('数量', '次'));
    expect(exerciseAmountLabel(rope), const ('数量', '个'));
  });

  test('isRepRecord: 次数型 key + 划线起算，旧记录仍按分钟', () {
    final cutoff = repUnitCutoffMs;
    expect(isRepRecord(key: 'pushup', createdAt: cutoff + 1000), true);
    expect(isRepRecord(key: 'rope', createdAt: cutoff), true);
    expect(isRepRecord(key: 'pushup', createdAt: cutoff - 1000), false);
    expect(isRepRecord(key: 'run', createdAt: cutoff + 1000), false);
    expect(isRepRecord(key: 'swim', createdAt: cutoff + 1000), false);
  });
}
