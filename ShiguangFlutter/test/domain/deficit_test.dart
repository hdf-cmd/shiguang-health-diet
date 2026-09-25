// ShiguangFlutter/test/domain/deficit_test.dart
// 逐条移植自 tests/logic.test.js #8：均值计算与最小天数门槛。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/deficit.dart';

void main() {
  test('avgDeficitFromRows: 均值计算与最小天数门槛', () {
    final rows = [
      {'intake': 1500, 'exKcal': 0},
      {'intake': 1400, 'exKcal': 100},
    ];
    final r = avgDeficitFromRows(2000, rows);
    expect(r, {'avgDeficit': 600, 'days': 2, 'tdee': 2000});
    expect(avgDeficitFromRows(2000, [rows[0]]), isNull); // <2 天
    expect(avgDeficitFromRows(2000, []), isNull);
  });
}
