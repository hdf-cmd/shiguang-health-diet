// ShiguangFlutter/lib/domain/js_compat.dart
// JS 数值语义兼容层：把 js/logic.js 里的 Math.round / toFixed / 模板字符串数字输出
// 逐位翻译到 Dart，保证 H5 与 Flutter 计算结果完全一致（双栈契约）。
// 分层铁律：本文件不得 import package:flutter。

/// JS Math.round(x) ≡ Math.floor(x + 0.5)（half 向 +∞ 取整，与 Dart 的“远离零”不同）
int jsRound(num x) => (x.toDouble() + 0.5).floor();

/// JS +(v).toFixed(1)：先按十进制字符串四舍五入到 1 位再转回数字
/// （对 38.849999999… 这类浮点下溢值，行为与 V8 的 toFixed 一致）
double jsFixed1(num v) => double.parse(v.toDouble().toStringAsFixed(1));

/// JS 模板字符串里的数字渲染：整数不带小数点（52 → "52"、52.0 → "52"），小数最短表示
String jsNumText(num v) {
  if (v is int) return '$v';
  final d = v.toDouble();
  if (d == d.roundToDouble() && d.isFinite) return d.round().toString();
  return '$d';
}

/// JS parseFloat 前缀语义（M6-T7 评审 F2）：取最长合法数字前缀，无合法前缀
/// 返回 NaN。与 num.tryParse 全串语义不等价——"1600." JS parseFloat=1600 而
/// tryParse=null；"16.2.3" parseFloat=16.2。goal-sheet 失焦归一 ≙
/// bindStepperNorm 的 parseFloat(el.value)，必须用本函数对齐 H5。
double jsParseFloat(String s) {
  final t = s.trimLeft(); // parseFloat 跳过前导空白
  final m = RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?')
      .firstMatch(t);
  if (m == null) return double.nan;
  var d = m.group(0)!;
  final neg = d.startsWith('-');
  if (neg || d.startsWith('+')) d = d.substring(1);
  if (d.startsWith('.')) d = '0$d'; // Dart parse 不接受 ".5"
  if (d.endsWith('.')) d = '${d}0'; // Dart parse 不接受 "5."
  return double.parse(d) * (neg ? -1 : 1);
}

/// JS Math.ceil
int jsCeil(num x) => x.toDouble().ceil();

/// JS Number(str) 全串语义（M6 终审 I1）：trim 后空串→0；整串须为合法十进制
/// 数字（'1600.'、'.5'、'1e3' 形态均可），否则返回 null（≙ NaN，调用方走
/// `||` 兜底）。与 jsParseFloat 前缀语义的差：'16.2.3' → NaN（前缀会得 16.2）。
/// H5 步进/保存链是 Number(el.value)（app.js:478/:1794/:1801/:1809），必须用
/// 本函数而非 num.tryParse（后者虽接受 '1600.'，但会拒绝 '1e3' 之外的 JS 形态
/// 并依赖平台实现，语义不受本仓控制）。
/// 已知不可达面：Number 的 '0x10'→16/Infinity 字面量——输入框字符类 [0-9.]
/// 拦住，不复刻。
num? jsNumber(String s) {
  final t = s.trim();
  if (t.isEmpty) return 0; // Number('')=0
  if (!RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$')
      .hasMatch(t)) {
    return null; // NaN
  }
  return jsParseFloat(t); // 全串校验已过，前缀解析可复用（吸收 '5.'/'.5'）
}

/// JS `x || fallback` 对字符串的 falsy 语义：null/空串→fallback（'0' 非空串
/// 原样返回 ≙ JS）。统一「e.message || '网络异常'」族口径（终审 Minor-1）。
String jsOr(String? s, String fallback) =>
    (s == null || s.isEmpty) ? fallback : s;
