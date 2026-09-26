// ShiguangFlutter/lib/features/common/sheet_toast.dart
// 弹层内浮层 toast（M6-T7 评审 F5：收敛 goal_sheet `_SheetToast` 与
// profile_screen `_ReminderToast` 两份近重复复制为单一来源，行为零变更；
// 防第三处再抄）。呈现层语义 ≙ H5 #toast 的弹层语境替代：fixed 底部居中、
// 盖在弹层之上、自隐——H5 toast 实为 1800ms（js/app.js:35
// `setTimeout(..., 1800)`），2400ms 为呈现层 R4 自主时长（F6 勘误，两处
// 原注释同口径修正）。Ticker（AnimationController）驱动而非裸 Timer：
// 测试 pumpAndSettle 会把它跑到自删，语义安全（goal_sheet T4 原注）。
import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 弹层内 toast 本体：OverlayEntry 的 builder 载荷，播完经 [onDone] 通知
/// 宿主删层。宿主职责不变：持有 OverlayEntry、开新 toast 前 remove 旧条、
/// dispose 时随层销毁。
class SheetToast extends StatefulWidget {
  const SheetToast({super.key, required this.msg, required this.onDone});

  final String msg;
  final VoidCallback onDone;

  @override
  State<SheetToast> createState() => _SheetToastState();
}

class _SheetToastState extends State<SheetToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 78),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 12),
    ]).animate(_c);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: Tokens.sp8),
          child: FadeTransition(
            opacity: opacity,
            child: Material(
              color: const Color(0xE632352D),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.sp4,
                  vertical: Tokens.sp2,
                ),
                child: Text(
                  widget.msg,
                  style: const TextStyle(
                    fontSize: Tokens.textSm,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
