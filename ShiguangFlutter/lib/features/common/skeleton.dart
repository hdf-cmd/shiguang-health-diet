// 公共骨架灰条（M9-A2）：纯静态底色 + 扫光。扫光只在真机跑；
// 测试全局关闭（test/flutter_test_config.dart 置 debugDisableLoadingAnimations），
// 避免无限动画让 pumpAndSettle 永不结束。
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'breathing_capsule.dart' show debugDisableLoadingAnimations;

class SkeletonBar extends StatefulWidget {
  const SkeletonBar({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.shimmer = true,
  });

  final double width;
  final double height;
  final bool shimmer;

  @override
  State<SkeletonBar> createState() => _SkeletonBarState();
}

class _SkeletonBarState extends State<SkeletonBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (widget.shimmer) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animate = widget.shimmer &&
        !reduceMotion &&
        !debugDisableLoadingAnimations;
    if (!animate && _c.isAnimating) _c.stop();

    final base = SizedBox(
      width: widget.width,
      height: widget.height,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: Tokens.surfaceSoft,
          borderRadius: BorderRadius.all(Radius.circular(Tokens.radiusSm)),
        ),
      ),
    );
    if (!animate) return base;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final x = -1.8 + 3.6 * _c.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(x - 0.55, 0),
            end: Alignment(x + 0.55, 0),
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: .55),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0, .5, 1],
          ).createShader(rect),
          child: child,
        );
      },
      child: base,
    );
  }
}
