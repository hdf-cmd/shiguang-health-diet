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
  // M1 终审 I1 收敛：阴影/大字进令牌，值逐字对照 css/design-tokens.css
  // --shadow-card（双层：0 1px 2px rgba(28,36,24,.04) + 0 10px 28px -14px rgba(28,36,24,.12)）
  // 与 --shadow-float（0 14px 44px -14px rgba(28,36,24,.26)）。
  test('--shadow-card 第二层主投影：alpha .12≈0x1F，blur 28 / offset (0,10) / spread -14', () {
    expect(Tokens.shadowCard[1].color.toARGB32(), 0x1F1C2418);
  });
  test('--shadow-float：alpha .26≈0x42，blur 44 / offset (0,14) / spread -14', () {
    expect(Tokens.shadowFloat.single.color.toARGB32(), 0x421C2418);
  });
  test('textHero = 登录/门控标题现用 40', () {
    expect(Tokens.textHero, 40.0);
  });
}
