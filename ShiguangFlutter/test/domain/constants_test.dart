// ShiguangFlutter/test/domain/constants_test.dart
// 领域常量移植守卫：值必须与 js/logic.js:10-48 逐字一致（唯一权威源）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/constants.dart';

void main() {
  test('餐次常量与 JS MEAL_ORDER/MEAL_NAMES/MEAL_IMG 一致', () {
    expect(mealOrder, ['breakfast', 'lunch', 'dinner', 'snack']);
    expect(mealNames, {
      'breakfast': '早餐', 'lunch': '午餐', 'dinner': '晚餐', 'snack': '零食',
    });
    expect(mealImg['breakfast'], 'img/meals/breakfast.jpg');
    expect(mealImg['lunch'], 'img/meals/lunch.jpg');
    expect(mealImg['dinner'], 'img/meals/dinner.jpg');
    expect(mealImg['snack'], 'img/meals/snack.jpg');
  });

  test('喝水常量：一杯 200ml，目标区间 800–3000（logic.test.js #12 断言 waterCupMl）', () {
    expect(waterCupMl, 200);
    expect(waterGoalMin, 800);
    expect(waterGoalMax, 3000);
  });

  test('活动系数表与代谢常量', () {
    expect(activity['sedentary']!.f, 1.2);
    expect(activity['light']!.f, 1.375);
    expect(activity['moderate']!.f, 1.55);
    expect(activity['active']!.f, 1.725);
    expect(activity['extreme']!.f, 1.9);
    expect(activity['light']!.label, '轻度');
    expect(kcalPerKg, 7700);
    expect(bodyDefault['heightCm'], 165);
    expect(bodyDefault['weightKg'], 55);
    expect(bodyDefault['bmi'], 20.2);
    expect(bodyDefault['age'], 28);
    expect(bodyDefault['gender'], 'female');
    expect(bodyDefault['activity'], 'light');
    expect(bodyDefault['deficit'], 500);
  });

  test('运动库 10 项：距离型带 perKgKm，时长型带 met，字段名与 JS 一致', () {
    expect(exerciseLib.length, 10);
    final run = exerciseLib.firstWhere((l) => l.key == 'run');
    final walk = exerciseLib[1]; // 建议规则 snack-over/meal-over 用 EXERCISE_LIB[1] 快走
    final swim = exerciseLib.firstWhere((l) => l.key == 'swim');
    expect(run.name, '跑步');
    expect(run.emoji, '🏃');
    expect(run.unit, 'km');
    expect(run.perKgKm, 1.036);
    expect(run.met, isNull);
    expect(walk.key, 'walk');
    expect(walk.unit, 'km');
    expect(walk.perKgKm, 0.5);
    expect(swim.unit, 'min');
    expect(swim.perKgKm, isNull);
    expect(swim.met, 8);
    // 逐项核对单位归类：前 3 距离型，其余 7 时长型
    expect(exerciseLib.where((l) => l.unit == 'km').map((l) => l.key).toList(),
        ['run', 'walk', 'cycle']);
    expect(exerciseLib.where((l) => l.unit == 'min').length, 7);
    expect(exerciseLib.firstWhere((l) => l.key == 'rope').met, 11);
    expect(exerciseLib.firstWhere((l) => l.key == 'yoga').met, 2.5);
  });
}
