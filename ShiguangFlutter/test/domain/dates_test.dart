// ShiguangFlutter/test/domain/dates_test.dart
// 逐条移植自 tests/dates.test.js（8 条）+ tests/logic.test.js #9（localIso/dateLabelOf）。
// 契约同 JS：本地时区安全（不用 UTC 切片）、「昨天」是唯一被特殊识别的口语标签、「今天」由调用方判断。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/dates.dart';

/// JS 的 setDate(getDate() - n)：日历日减法，等价于用 (day - n) 构造（DateTime 会自动规范化跨月/跨年）
DateTime _dayOffset(int n) {
  final t = DateTime.now();
  return DateTime(t.year, t.month, t.day + n);
}

void main() {
  /* ---------- localIso ---------- */

  test('localIso: 月/日补零，输出 YYYY-MM-DD', () {
    expect(localIso(DateTime(2026, 1, 5)), '2026-01-05');
    expect(localIso(DateTime(2026, 10, 9)), '2026-10-09');
    expect(localIso(DateTime(2026, 12, 31)), '2026-12-31');
  });

  test('localIso: 同一天的凌晨与深夜都落在同一天（不随 UTC 偏移跳天）', () {
    expect(localIso(DateTime(2026, 1, 1, 0, 0, 1)), '2026-01-01');
    expect(localIso(DateTime(2026, 1, 1, 23, 59, 59)), '2026-01-01');
    // 跨年边界同理
    expect(localIso(DateTime(2026, 12, 31, 23, 59, 59)), '2026-12-31');
    expect(localIso(DateTime(2027, 1, 1, 0, 0, 1)), '2027-01-01');
  });

  test('localIso: 闰年 2 月 29 日', () {
    expect(localIso(DateTime(2028, 2, 29)), '2028-02-29');
    expect(localIso(DateTime(2028, 3, 1)), '2028-03-01');
  });

  test('todayIso: 恒等于当前本地日期（默认时钟）', () {
    expect(todayIso(), localIso(DateTime.now()));
  });

  test('todayIso: 接受可注入 DateTime（Dart 侧新增，便于上层确定性测试）', () {
    expect(todayIso(DateTime(2026, 9, 15, 22, 30)), '2026-09-15');
  });

  /* ---------- dateLabelOf ---------- */

  test('dateLabelOf: 昨天返回「昨天」', () {
    expect(dateLabelOf(localIso(_dayOffset(-1))), '昨天');
  });

  test('dateLabelOf: 今天不返回「昨天」（本函数不识别今天，由调用方判断）', () {
    final today = DateTime.now();
    final label = dateLabelOf(localIso(today));
    expect(label == '昨天', isFalse);
    expect(label, '${today.month}月${today.day}日');
  });

  test('dateLabelOf: 更早的日期返回「M月D日」（不补零，含跨月固定用例）', () {
    final d2 = _dayOffset(-2); // 前天，永远不可能是「昨天」，避免测试随日期漂移
    expect(dateLabelOf(localIso(d2)), '${d2.month}月${d2.day}日');
    expect(dateLabelOf('2026-03-01'), '3月1日');
    expect(dateLabelOf('2026-12-31'), '12月31日');
  });

  test('dateLabelOf: 按本地时间解析日期串（避免 UTC 解析把日期挪走）', () {
    expect(dateLabelOf('2026-01-01'), '1月1日');
    expect(dateLabelOf('2026-06-15'), '6月15日');
  });

  /* ---------- 来自 logic.test.js #9 ---------- */

  test('localIso/dateLabelOf: 本地时区安全与口语标签（logic.test.js #9）', () {
    expect(localIso(DateTime(2026, 9, 15)), '2026-09-15');
    expect(dateLabelOf(localIso(_dayOffset(-1))), '昨天');
  });
}
