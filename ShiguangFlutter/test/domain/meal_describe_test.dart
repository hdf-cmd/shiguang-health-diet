import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/meal_describe.dart';

void main() {
  group('initialMealAmount', () {
    final per100Food = <String, dynamic>{'per100': {'kcal': 100}, 'baseG': 50};

    test('用户说克/毫升时直接用', () {
      expect(initialMealAmount({'quantity': 120, 'unit': 'g'}, per100Food), 120);
      expect(initialMealAmount({'quantity': 250, 'unit': 'ml'}, per100Food), 250);
    });

    test('用户说个数/份数时乘以默认份量', () {
      expect(initialMealAmount({'quantity': 2}, per100Food), 100);
      expect(initialMealAmount({'quantity': 1, 'unit': 'serving'}, per100Food), 50);
    });

    test('没说数量时用默认份量，缺 baseG 回退 100', () {
      expect(initialMealAmount({}, per100Food), 50);
      expect(initialMealAmount({}, {'per100': {'kcal': 100}}), 100);
    });

    test('无 per100 的旧自定义食物按份处理', () {
      expect(initialMealAmount({'quantity': 2}, {'kcal': 78}), 2);
      expect(initialMealAmount({}, {'kcal': 78}), 1);
    });

    test('无命中且无数量时默认 1 份', () {
      expect(initialMealAmount({}, null), 1);
    });
  });

  test('servingNutritionFromPer100：按每 100g 换算到这一份', () {
    final s = servingNutritionFromPer100(
      const {'kcal': 89, 'protein': 3.1, 'carb': 12, 'fat': 3.1},
      grams: 200,
    );
    expect(s.grams, 200);
    expect(s.kcal, 178);
    expect(s.protein, 6.2);
    expect(s.carb, 24);
    expect(s.fat, 6.2);

    final fallback = servingNutritionFromPer100(
      const {'kcal': 100, 'protein': 10, 'carb': 10, 'fat': 10},
    );
    expect(fallback.grams, 100);
    expect(fallback.kcal, 100);
  });

  test('formatMealAmount 整数不带小数，其余一位', () {
    expect(formatMealAmount(100), '100');
    expect(formatMealAmount(100.0), '100');
    expect(formatMealAmount(2.5), '2.5');
  });

  test('mealMatchesOf 优先 matches，旧响应退化为单候选，空时为空表', () {
    final a = <String, dynamic>{'name': '米饭'};
    final b = <String, dynamic>{'name': '米饭（大份）'};
    expect(
      mealMatchesOf({'matches': [a, b]}, null).map((e) => e['name']).toList(),
      ['米饭', '米饭（大份）'],
    );
    expect(mealMatchesOf({}, a).single['name'], '米饭');
    expect(mealMatchesOf({}, null), isEmpty);
  });
}
