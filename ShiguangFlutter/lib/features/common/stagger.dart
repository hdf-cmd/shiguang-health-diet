// ShiguangFlutter/lib/features/common/stagger.dart
// M9-B2：错峰入场——首 build 播 translateY(14)+fade 220ms easeOutCubic，
// delay 40ms×index。**只播一次**（State 布尔；数据刷新/切日期 rebuild 不
// 重播，防回访骚扰；页面重建=新 State 重播属预期，spec §4 B6 亦由此达成）。
// M9-T6 接线兼容：delay 改持可取消 Timer 句柄并在 dispose 取消——
// Future.delayed 的裸定时器在「树仍在体、用例收竿」时触发 flutter_test
// 「A Timer is still pending」不变量（页面测试的定步 pump 定式无法为此
// 破例）；取消语义与 _cDisposed 守卫同口径（dispose 后本就不播），
// T5 钉②「到点不炸」依旧成立（定时器不再到点）。
import 'dart:async';

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
  // I-1：guard 显式对准「_c 是否已 dispose」——forward 在 dispose 后到点是
  // debug assert 级崩溃（AnimationController methods should not be used after
  // calling dispose），dispose 场景由 _cDisposed 直接挡掉、静默不炸；
  // deactivate/reparent 场景（Sliver 保活窗口）controller 存活，照常播。
  // 不用 mounted 做代理：State.mounted 要到 unmount 尾部才转 false（framework
  // 内部时序），语义上隔了一层，且随框架实现演化存在被改写的风险。
  bool _cDisposed = false;
  /// delay 定时器句柄（M9-T6）：dispose 即 cancel，不留裸 pending timer。
  Timer? _startTimer;
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
    _startTimer = Timer(Duration(milliseconds: 40 * widget.index), () {
      // I-1：守卫=「controller 已 dispose」而非 mounted（见 _cDisposed 注释）。
      // 本 Flutter 版本（3.47.5）AnimationController 无公开 isDisposed getter
      // （framework 源码 grep 实证，仅 CurvedAnimation 有），故以 State 自持
      // _cDisposed 标志实现同语义。
      if (!_cDisposed) _c.forward();
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel(); // M9-T6：dispose 即取消未到点 delay（防 pending timer）
    _cDisposed = true;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}
