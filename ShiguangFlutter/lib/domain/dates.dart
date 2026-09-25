// ShiguangFlutter/lib/domain/dates.dart
// 日期工具。唯一权威源：js/logic.js:50-64（本地时区安全：不用 UTC 切片，避免跳天）。
// 与 JS 的差异：todayIso 接受可注入 DateTime（Dart 测试确定性需要），默认 DateTime.now()。
// 分层铁律：本文件不得 import package:flutter。

String _two(int n) => n.toString().padLeft(2, '0');

/// 本地字段拼 YYYY-MM-DD（等价 JS localIso）
String localIso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// 今天（本地时区）
String todayIso([DateTime? now]) => localIso(now ?? DateTime.now());

/// 日期口语标签：昨天 → 「昨天」，其余 → 「M月D日」。
/// 注意：本函数不识别「今天」，调用方需自行判断（对齐 js/logic.js:57-58 注释）。
String dateLabelOf(String iso, [DateTime? now]) {
  final ref = now ?? DateTime.now();
  // JS: const yd = new Date(); yd.setDate(yd.getDate() - 1); —— 日历日减一
  final yd = DateTime(ref.year, ref.month, ref.day - 1);
  if (iso == localIso(yd)) return '昨天';
  // JS: new Date(iso + 'T00:00:00') —— 无 Z 后缀按本地时间解析；Dart 同语义
  final d = DateTime.parse('${iso}T00:00:00');
  return '${d.month}月${d.day}日';
}
