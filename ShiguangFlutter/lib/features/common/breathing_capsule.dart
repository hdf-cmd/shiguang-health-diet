// 加载态公共件：呼吸胶囊 + 按钮内联小环。
// 胶囊用于页面/旁路的“正在取数”，小环用于写操作的按钮在途。
// 两者都尊重系统「移除动画」无障碍设置；测试可传 animate:false 走静态。
import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 测试开关：置 true 时呼吸/旋转都走静态帧，避免长期加载态让
/// `pumpAndSettle` 永不结束。生产恒为 false。
bool debugDisableLoadingAnimations = false;

class BreathingCapsule extends StatefulWidget {
  const BreathingCapsule({
    super.key,
    this.minWidth = 64,
    this.maxWidth = 148,
    this.height = 6,
    this.color = Tokens.primary,
    this.glow = true,
    this.animate = true,
  });

  final double minWidth;
  final double maxWidth;
  final double height;
  final Color color;
  final bool glow;
  final bool animate;

  @override
  State<BreathingCapsule> createState() => _BreathingCapsuleState();
}

class _BreathingCapsuleState extends State<BreathingCapsule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant BreathingCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _c.repeat(reverse: true);
      } else {
        _c.stop();
        _c.value = 0.5;
      }
    }
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
    final animated = widget.animate &&
        !reduceMotion &&
        !debugDisableLoadingAnimations;
    if (!animated && _c.isAnimating) _c.stop();

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = animated ? Curves.easeInOut.transform(_c.value) : 0.5;
        final w = widget.minWidth + (widget.maxWidth - widget.minWidth) * t;
        return Container(
          width: w,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: [
                widget.color.withValues(alpha: 0.55),
                widget.color,
              ],
            ),
            boxShadow: widget.glow
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.22 + 0.12 * t),
                      blurRadius: 10,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

/// 按钮内联 loading：16dp 小环，颜色跟随按钮前景。
class LoadingSpinner extends StatelessWidget {
  const LoadingSpinner({
    super.key,
    this.size = 16,
    this.color = Colors.white,
    this.strokeWidth = 2,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          // 非空 value = 静态圆弧，测试里可让 pumpAndSettle 正常结束
          value: debugDisableLoadingAnimations ? 0.7 : null,
          strokeWidth: strokeWidth,
          color: color,
          backgroundColor: color.withValues(alpha: 0.18),
        ),
      );
}
