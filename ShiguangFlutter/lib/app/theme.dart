// ShiguangFlutter/lib/app/theme.dart
import 'package:flutter/material.dart';

/// 食光设计令牌。唯一事实来源：仓库根 css/design-tokens.css，此文件为其 Dart 镜像，
/// 值必须逐字一致（theme_test 抽查把关）。
abstract class Tokens {
  // 色彩 · 中性
  static const bg = Color(0xFFF4F5F0);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFFBFCF9);
  static const surfaceSoft = Color(0xFFEDF1E8);
  static const ink = Color(0xFF1C2418);
  static const ink2 = Color(0xFF55624C);
  static const ink3 = Color(0xFF8E9B84);
  static const line = Color(0xFFE4E9DC);
  // 色彩 · 品牌
  static const primary = Color(0xFF356B45);
  static const primaryDeep = Color(0xFF234D30);
  static const primarySoft = Color(0xFFE3EFE0);
  // 色彩 · 营养素 / 语义
  static const nutCarb = Color(0xFFD99A34);
  static const nutProtein = Color(0xFFBF5B4B);
  static const nutFat = Color(0xFF5B8CA6);
  static const warn = Color(0xFFCE5F26);
  static const warnSoft = Color(0xFFF8E4D6);
  static const danger = Color(0xFFB23A2C);
  // 圆角
  static const radiusSm = 12.0;
  static const radiusMd = 18.0;
  static const radiusLg = 26.0;
  static const radiusSheet = 30.0;
  // 间距（4 基准）
  static const sp1 = 4.0, sp2 = 8.0, sp3 = 12.0, sp4 = 16.0;
  static const sp5 = 20.0, sp6 = 24.0, sp8 = 32.0;
  // 字号
  static const textXs = 11.0, textSm = 13.0, textMd = 15.0, textLg = 17.0;
  static const textXl = 24.0, textNum = 46.0;
}

ThemeData shiguangTheme() {
  final base = ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(
      seedColor: Tokens.primary, primary: Tokens.primary, surface: Tokens.surface));
  return base.copyWith(
    scaffoldBackgroundColor: Tokens.bg,
    textTheme: base.textTheme
        .apply(bodyColor: Tokens.ink, displayColor: Tokens.ink)
        .copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(
              fontSize: Tokens.textLg, fontWeight: FontWeight.w700),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: Tokens.textMd),
        ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Tokens.primaryDeep,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusSheet)),
        textStyle: const TextStyle(fontSize: Tokens.textMd, fontWeight: FontWeight.w700),
      )),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tokens.surface2,
      hintStyle: const TextStyle(color: Tokens.ink3, fontSize: Tokens.textSm),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: Tokens.sp4, vertical: Tokens.sp4),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          borderSide: const BorderSide(color: Tokens.line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          borderSide: const BorderSide(color: Tokens.line)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
