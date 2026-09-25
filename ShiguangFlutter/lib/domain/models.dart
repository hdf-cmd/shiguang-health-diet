// ShiguangFlutter/lib/domain/models.dart
// 共享数据类。字段名与云函数返回逐字一致（kcal/target/carb/protein/fat/water、
// heightCm/weightKg/bmi/age/gender/activity/deficit），后续 ApiClient 直接映射。
// 分层铁律：本文件不得 import package:flutter。

/// 身体档案（对应 H5 state.body / 云函数 body 文档）
class Body {
  const Body({
    required this.heightCm,
    required this.weightKg,
    required this.age,
    required this.gender,
    required this.activity,
    required this.deficit,
    this.bmi,
  });

  /// 从云函数/本地存储的 Map 构造（缺字段时回退 js/logic.js BODY_DEFAULT 语义由调用方保证）
  factory Body.fromMap(Map<String, Object?> m) => Body(
        heightCm: (m['heightCm'] as num?) ?? 165,
        weightKg: (m['weightKg'] as num?) ?? 55,
        age: (m['age'] as num?)?.toInt() ?? 28,
        gender: (m['gender'] as String?) ?? 'female',
        activity: (m['activity'] as String?) ?? 'light',
        deficit: (m['deficit'] as num?) ?? 500,
        bmi: m['bmi'] as num?,
      );

  final num heightCm;
  final num weightKg;
  final int age;
  final String gender;
  final String activity;
  final num deficit;
  final num? bmi;

  Map<String, Object?> toMap() => {
        'heightCm': heightCm,
        'weightKg': weightKg,
        'age': age,
        'gender': gender,
        'activity': activity,
        'deficit': deficit,
        if (bmi != null) 'bmi': bmi,
      };
}

/// 某日摄入汇总（对应 HealthAPI.getDailySummary 返回结构）
class Summary {
  const Summary({
    required this.kcal,
    required this.target,
    required this.carb,
    required this.protein,
    required this.fat,
    required this.water,
  });

  factory Summary.fromMap(Map<String, Object?> m) => Summary(
        kcal: (m['kcal'] as num?) ?? 0,
        target: (m['target'] as num?) ?? 0,
        carb: (m['carb'] as num?) ?? 0,
        protein: (m['protein'] as num?) ?? 0,
        fat: (m['fat'] as num?) ?? 0,
        water: (m['water'] as num?) ?? 0,
      );

  final num kcal;
  final num target;
  final num carb;
  final num protein;
  final num fat;

  /// 杯数（× waterCupMl 得毫升）
  final num water;

  Map<String, Object?> toMap() => {
        'kcal': kcal,
        'target': target,
        'carb': carb,
        'protein': protein,
        'fat': fat,
        'water': water,
      };
}
