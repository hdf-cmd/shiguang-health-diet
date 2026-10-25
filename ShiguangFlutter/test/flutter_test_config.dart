import 'dart:async';

import 'package:shiguang_flutter/features/common/breathing_capsule.dart'
    show debugDisableLoadingAnimations;

/// 全局测试配置：骨架扫光、呼吸胶囊、按钮小环统一走静态帧。
/// 这些是无限循环动画，开启会让 pumpAndSettle 永远等不到稳定态。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugDisableLoadingAnimations = true;
  await testMain();
}
