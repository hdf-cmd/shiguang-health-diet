// ShiguangFlutter/lib/features/common/stagger.dart
// M9-B2：错峰入场——首 build 播 translateY(14)+fade 220ms easeOutCubic，
// delay 40ms×index。**只播一次**（State 布尔；数据刷新/切日期 rebuild 不
// 重播，防回访骚扰；页面重建=新 State 重播属预期，spec §4 B6 亦由此达成）。
import 'package:flutter/material.dart';

class Stagger extends StatefulWidget {
  const Stagger({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<Stagger> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  bool _played = false;
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide = Tween<Offset>(
          begin: const Offset(0, 0.06), end: Offset.zero)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _playOnce();
  }

  /// 本实例只自动播一次；State 复用下的 rebuild 不再经过此处。
  void _playOnce() {
    if (_played) return;
    _played = true;
    Future.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}
