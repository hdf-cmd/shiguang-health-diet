// ShiguangFlutter/lib/domain/exercise.dart
// 运动消耗。唯一权威源：js/logic.js（exerciseKcalOf/EXERCISE_LIB/
// exerciseAmountLabel/isRepRecord）。
//   距离型 = 系数 × 体重 × 距离；次数型 = 系数 × 体重 × 次数；
//   时长型 = MET × 3.5 × 体重 / 200 × 分钟
// 乘法顺序与 JS 逐字一致，保证浮点结果逐位相同。
// 分层铁律：本文件不得 import package:flutter。
import 'package:shiguang_flutter/domain/constants.dart';
import 'package:shiguang_flutter/domain/js_compat.dart';

/// [weightKg] 为 null（JS undefined）或 0（JS falsy）时回退 55kg
int exerciseKcalOf(Exercise lib, num amount, num? weightKg) {
  final w = (weightKg == null || weightKg == 0) ? 55 : weightKg;
  if (lib.unit == 'km') return jsRound(lib.perKgKm! * w * amount);
  if (lib.unit == 'rep') return jsRound(lib.perRepKg! * w * amount);
  return jsRound(lib.met! * 3.5 * w / 200 * amount);
}

/// 弹层输入控件的标题与单位（三型各自）。返回 (name, unit) record。
(String, String) exerciseAmountLabel(Exercise lib) {
  if (lib.unit == 'km') return ('距离', 'km');
  if (lib.unit == 'rep') return ('数量', lib.repUnit ?? '次');
  return ('时长', '分钟');
}

/// 次数型划线（epoch ms）：与 js/logic.js REP_UNIT_CUTOFF 同一定义式。
/// 此前创建的 pushup/rope 记录记的是分钟，仍按分钟显示。
final int repUnitCutoffMs =
    DateTime.parse('2026-09-25T00:00:00+08:00').millisecondsSinceEpoch;

const _repKeys = {'pushup', 'rope'};

/// 该记录是否按"次数"展示（云端 unit 白名单只认 km/min，rep 落库即 min，
/// 故判别靠 key + createdAt，与 H5 isRepRecord 同构）
bool isRepRecord({required String key, required int createdAt}) =>
    _repKeys.contains(key) && createdAt >= repUnitCutoffMs;
