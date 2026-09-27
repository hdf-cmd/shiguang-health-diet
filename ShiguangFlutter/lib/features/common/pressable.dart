// ShiguangFlutter/lib/features/common/pressable.dart
// M9-B1（R4 视觉自主位）：按压微缩回弹——按下 120ms 收至 0.975，
// 松手 260ms elasticOut 回弹。只包无内部手势的容器位（spec §7 风险条）；
// 行内钮（✕/删除）保持自身手势不叠。
import 'package:flutter/material.dart';

class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.onTap, required this.child});
  final VoidCallback? onTap;
  final Widget child;
  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;
  void _set(bool v) { if (mounted && _down != v) setState(() => _down = v); }
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _down ? 0.975 : 1.0,
          duration: Duration(milliseconds: _down ? 120 : 260),
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: widget.child,
        ),
      );
}
