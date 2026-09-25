// ShiguangFlutter/lib/domain/constants.dart
// 领域常量表。唯一权威源：js/logic.js:10-48，值与字段名（unit/perKgKm/met）逐字对齐。
// 分层铁律：本文件不得 import package:flutter。

/// 餐次顺序（记录页/汇总遍历用）
const mealOrder = ['breakfast', 'lunch', 'dinner', 'snack'];

/// 餐次中文名
const mealNames = <String, String>{
  'breakfast': '早餐',
  'lunch': '午餐',
  'dinner': '晚餐',
  'snack': '零食',
};

/// 餐次图标路径（对应 H5 assets img/meals/*.jpg，Flutter 侧资源映射后续任务处理）
const mealImg = <String, String>{
  'breakfast': 'img/meals/breakfast.jpg',
  'lunch': 'img/meals/lunch.jpg',
  'dinner': 'img/meals/dinner.jpg',
  'snack': 'img/meals/snack.jpg',
};

/* ---------- 喝水 ---------- */
const waterCupMl = 200;
const waterGoalMin = 800;
const waterGoalMax = 3000;

/* ---------- 代谢 ---------- */

/// 活动系数档位（Mifflin-St Jeor 的乘数）
class ActivityLevel {
  const ActivityLevel(this.f, this.label);
  final double f;
  final String label;
}

const activity = <String, ActivityLevel>{
  'sedentary': ActivityLevel(1.2, '久坐'),
  'light': ActivityLevel(1.375, '轻度'),
  'moderate': ActivityLevel(1.55, '中度'),
  'active': ActivityLevel(1.725, '重度'),
  'extreme': ActivityLevel(1.9, '极大'),
};

/// 减 1kg 体脂约需缺口
const kcalPerKg = 7700;

/// 身体档案默认值（键名与云函数返回一致，Body 数据类见 models.dart）
const bodyDefault = <String, Object>{
  'heightCm': 165,
  'weightKg': 55,
  'bmi': 20.2,
  'age': 28,
  'gender': 'female',
  'activity': 'light',
  'deficit': 500,
};

/* ---------- 运动库（距离型 perKgKm；时长型 MET） ---------- */

/// 运动库条目：unit 为 'km' 时用 [perKgKm]，为 'min' 时用 [met]，字段名与 JS 逐字一致。
class Exercise {
  const Exercise({
    required this.key,
    required this.name,
    required this.emoji,
    required this.unit,
    this.perKgKm,
    this.met,
  });

  final String key;
  final String name;
  final String emoji;
  final String unit;
  final double? perKgKm;
  final double? met;
}

const exerciseLib = <Exercise>[
  Exercise(key: 'run', name: '跑步', emoji: '🏃', unit: 'km', perKgKm: 1.036),
  Exercise(key: 'walk', name: '快走', emoji: '🚶', unit: 'km', perKgKm: 0.5),
  Exercise(key: 'cycle', name: '骑行', emoji: '🚴', unit: 'km', perKgKm: 0.35),
  Exercise(key: 'swim', name: '游泳', emoji: '🏊', unit: 'min', met: 8),
  Exercise(key: 'pushup', name: '俯卧撑', emoji: '💪', unit: 'min', met: 8),
  Exercise(key: 'strength', name: '力量训练', emoji: '🏋️', unit: 'min', met: 5),
  Exercise(key: 'yoga', name: '瑜伽', emoji: '🧘', unit: 'min', met: 2.5),
  Exercise(key: 'rope', name: '跳绳', emoji: '🤸', unit: 'min', met: 11),
  Exercise(key: 'hiit', name: 'HIIT', emoji: '🔥', unit: 'min', met: 8),
  Exercise(key: 'ball', name: '球类', emoji: '🏀', unit: 'min', met: 7),
];
