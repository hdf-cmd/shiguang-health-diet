// ShiguangFlutter/test/domain/js_compat_test.dart
// M6-T7 评审 F2：jsParseFloat 钉 JS parseFloat 前缀语义——与 Dart
// num.tryParse 全串语义的分歧样本（"1600."、"16.2.3"）逐支锁死；
// goal-sheet 失焦归一（bindStepperNorm ≙ app.js:1639-1644）依赖此语义。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/js_compat.dart'
    show jsNumber, jsOr, jsParseFloat;

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

  // M6 终审 I1：Number() 全串语义（步进/保存链 ≙ app.js:478/:1794/:1801/:1809）
  test('jsNumber ≙ JS Number(str) 全串语义（jsParseFloat 的前缀差被全串闸锁死）',
      () {
    expect(jsNumber('1600.'), 1600); // 主分歧样本：tryParse=null
    expect(jsNumber('5.'), 5); // 运动量步进链同款
    expect(jsNumber(''), 0); // Number('')=0（非 NaN）
    expect(jsNumber(' 42 '), 42); // 两侧空白 trim
    expect(jsNumber('.5'), 0.5);
    expect(jsNumber('1e3'), 1000);
    expect(jsNumber('-10'), -10);
    expect(jsNumber('16.2.3'), isNull); // 全串非法→NaN（前缀语义会给 16.2）
    expect(jsNumber('abc'), isNull);
    expect(jsNumber('1abc'), isNull); // Number 不取前缀（parseFloat=1）
  });

  test('jsOr ≙ JS `x || fallback` 字符串 falsy 语义（终审 Minor-1 统一口径）',
      () {
    expect(jsOr('', '网络异常'), '网络异常'); // 空串→兜底
    expect(jsOr(null, '网络异常'), '网络异常');
    expect(jsOr('boom', '网络异常'), 'boom');
    expect(jsOr('0', '网络异常'), '0'); // '0' 非空串原样（≙ JS truthy string）
  });
}
