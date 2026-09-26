// ShiguangFlutter/test/domain/js_compat_test.dart
// M6-T7 评审 F2：jsParseFloat 钉 JS parseFloat 前缀语义——与 Dart
// num.tryParse 全串语义的分歧样本（"1600."、"16.2.3"）逐支锁死；
// goal-sheet 失焦归一（bindStepperNorm ≙ app.js:1639-1644）依赖此语义。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/js_compat.dart' show jsParseFloat;

void main() {
  test('jsParseFloat ≙ JS parseFloat 前缀语义（含 tryParse 分歧支）', () {
    expect(jsParseFloat('1600.'), 1600); // tryParse=null（分歧主样本）
    expect(jsParseFloat('16.2.3'), 16.2); // 前缀截断，tryParse=null
    expect(jsParseFloat('2000'), 2000); // 双方一致支
    expect(jsParseFloat('.5'), 0.5); // JS parseFloat('.5')=0.5
    expect(jsParseFloat('+.5e2'), 50); // 符号+前导点+指数前缀
    expect(jsParseFloat('-10'), -10);
    expect(jsParseFloat('1e3'), 1000);
    expect(jsParseFloat(' 42'), 42); // 跳过前导空白
    expect(jsParseFloat(''), double.nan); // 无合法前缀 → NaN（≙ isNaN→min 支）
    expect(jsParseFloat('.'), double.nan);
    expect(jsParseFloat('abc'), double.nan);
  });
}
