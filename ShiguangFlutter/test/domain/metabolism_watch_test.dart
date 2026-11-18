// ShiguangFlutter/test/domain/metabolism_watch_test.dart
// 手表口径：TDEE = BMR + 手表全天活动（>0 时启用），预估时间随实际缺口联动。
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/constants.dart' show bodyDefault;
import 'package:shiguang_flutter/domain/metabolism.dart';
import 'package:shiguang_flutter/domain/models.dart';

Body body() => Body.fromMap(Map<String, Object?>.from(bodyDefault));

void main() {
  test('无手表数据：回落 BMR×活动系数，tdeeFromWatch=false', () {
    final m = computeMetabolism(body(), 75);
    expect(m.tdeeFromWatch, false);
    expect(m.tdee, (m.bmr * 1.375).round());
  });

  test('有手表活动：TDEE = BMR + 手表活动', () {
    final m = computeMetabolism(body(), 75, null, null, 255);
    expect(m.tdeeFromWatch, true);
    expect(m.tdee, m.bmr + 255);
    // 建议摄入 = max(TDEE - 缺口, 安全下限, BMR)
    final floor = bodyDefault['gender'] == 'female' ? 1200 : 1500;
    expect(m.suggest, math.max(m.tdee - 500, math.max(floor, m.bmr)));
  });

  test('手表活动 0 或负值 → 视为无数据，回落系数口径', () {
    final zero = computeMetabolism(body(), 75, null, null, 0);
    final neg = computeMetabolism(body(), 75, null, null, -10);
    final none = computeMetabolism(body(), 75);
    expect(zero.tdeeFromWatch, false);
    expect(neg.tdeeFromWatch, false);
    expect(zero.tdee, none.tdee);
    expect(neg.tdee, none.tdee);
  });

  test('实际缺口支：预计时间按 avgDeficit 计算，watch 口径同源', () {
    final m = computeMetabolism(
        body(), 50, {'avgDeficit': 400, 'days': 5}, DateTime(2026, 11, 18), 300);
    expect(m.useActual, true);
    expect(m.effDeficit, 400);
    expect(m.etaText, contains('按近 5 天实际日均缺口 400 kcal 估算'));
  });
}
