// ShiguangFlutter/test/theme_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart';

void main() {
  test('令牌与 css/design-tokens.css 逐字一致（抽查关键色）', () {
    expect(Tokens.bg.toARGB32(), 0xFFF4F5F0);
    expect(Tokens.primary.toARGB32(), 0xFF356B45);
    expect(Tokens.primaryDeep.toARGB32(), 0xFF234D30);
    expect(Tokens.ink.toARGB32(), 0xFF1C2418);
    expect(Tokens.warn.toARGB32(), 0xFFCE5F26);
    expect(Tokens.nutCarb.toARGB32(), 0xFFD99A34);
    expect(Tokens.radiusLg, 26.0);
    expect(Tokens.sp4, 16.0);
  });
  test('主题使用令牌作为 scaffold 背景与主色', () {
    final t = shiguangTheme();
    expect(t.scaffoldBackgroundColor, Tokens.bg);
    expect(t.colorScheme.primary, Tokens.primary);
  });
}
