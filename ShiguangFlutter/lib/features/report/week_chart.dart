// ShiguangFlutter/lib/features/report/week_chart.dart
// 周/期柱状图（M3 Task 4）。几何逐字对齐 H5：
//   max        = Math.max(...kcal, target) * 1.1        （js/app.js:790）
//   柱高%      = Math.max(4, kcal/max*100)              （js/app.js:798，0 kcal 也占 4%）
//   目标虚线   = bottom: target/max*100%                （js/app.js:795）
//   今天柱标签 "今天"，over 类 = kcal > target           （js/app.js:797-799）
//   容器高 140 / 柱列 gap 10 / 柱 max-width 22 / 圆角 7 7 3 3 /
//   transition height .7s --ease-out                    （css/screens.css:407-417）
// 点击气泡（app.js:821-829）：选中态为单一 index，由父级持有 ValueNotifier<int?>，
// 本组件只读 notifier 渲染气泡并把点击上报给 onBarTap（互斥+再点收起在父侧做）。
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/report.dart';

class WeekBarChart extends StatelessWidget {
  const WeekBarChart({
    super.key,
    required this.data,
    required this.todayIndex,
    required this.selectedIndex,
    required this.onBarTap,
  });

  final ReportData data;

  /// weekTodayIndex(now)（周一=0…周日=6）；月视图等不高亮场景传 -1
  final int todayIndex;

  /// 选中柱 index（null=全收起）。父级持有：互斥、再点同柱收起。
  final ValueListenable<int?> selectedIndex;

  final ValueChanged<int> onBarTap;

  static const double _chartHeight = 140; // .week-chart height:140px
  static const double _barWidth = 22; // .bar max-width:22px
  static const double _colGap = 10; // .week-chart gap:10px
  static const double _barGap = 6; // .col gap:6px（柱↔标签）
  static const Duration _heightAnim = Duration(milliseconds: 700);
  /// css --ease-out: cubic-bezier(.16, 1, .3, 1)（design-tokens.css:84）
  static const Curve _easeOut = Cubic(0.16, 1, 0.3, 1);

  @override
  Widget build(BuildContext context) {
    final kcal = data.kcal;
    // H5 Math.max(...r.kcal, r.target)：kcal 全体与 target 取大再 ×1.1
    final max =
        math.max(kcal.fold(0, math.max), data.target) * 1.1;

    final barChildren = <Widget>[];
    final labelChildren = <Widget>[];
    for (var i = 0; i < kcal.length; i++) {
      if (i > 0) {
        barChildren.add(const SizedBox(width: _colGap));
        labelChildren.add(const SizedBox(width: _colGap));
      }
      barChildren.add(Expanded(child: _barColumn(i, kcal[i], max)));
      labelChildren.add(Expanded(child: _label(i)));
    }

    return Column(
      children: [
        SizedBox(
          height: _chartHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 目标虚线：H5 innerHTML 里 target-line 在柱之前 → 柱盖在线上
              Positioned(
                left: 0,
                right: 0,
                bottom: data.target / max * _chartHeight,
                child: _targetLine(),
              ),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: barChildren),
            ],
          ),
        ),
        // H5 .col 内部 lbl 与柱同列（gap 6）；Flutter 侧标签行在 140 轴下方，
        // 保证柱高%与目标线%共用同一 140 基准（浏览器里 flex-shrink 会压柱，
        // 该拆法即 H5 意图的无挤压等价形）。
        const SizedBox(height: _barGap),
        Row(children: labelChildren),
        // .week-chart border-bottom:1px solid --hairline（screens.css:407
        // 图表轴线；终审 Important-1）——border-bottom 画在 140 容器**最底沿**，
        // 而 .lbl 在 .col 内部（app.js:796-800）→ 浏览器里轴线在日期标签**之下**。
        // 故这条线排在标签行之后，不是柱区与标签之间。
        const SizedBox(
          width: double.infinity,
          height: 1,
          child: ColoredBox(
            key: ValueKey('week-chart-axis'),
            color: Tokens.hairline,
          ),
        ),
      ],
    );
  }

  /// 单根柱：TweenAnimationBuilder 0→pct 入场（700ms ease-out，等价
  /// css transition: height .7s；数据变化时同一元素自动从旧值补间到新值）
  Widget _barColumn(int i, int kcal, double max) {
    final pct = math.max(4.0, kcal / max * 100); // app.js:798 min 4
    return ValueListenableBuilder<int?>(
      valueListenable: selectedIndex,
      builder: (context, selected, _) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: pct),
          duration: _heightAnim,
          curve: _easeOut,
          builder: (context, animatedPct, _) {
            final h = animatedPct / 100 * _chartHeight;
            return Align(
              alignment: Alignment.bottomCenter,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  GestureDetector(
                    key: ValueKey('week-bar-$i'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onBarTap(i),
                    child: Container(
                      key: ValueKey('week-bar-fill-$i'),
                      width: _barWidth,
                      height: h,
                      decoration: _barDecoration(i, kcal),
                    ),
                  ),
                  // .bar-val：absolute bottom calc(100%+3px)（screens.css:421），
                  // 不占布局；val-on 才显示 → 未选中不进树
                  if (selected == i)
                    Positioned(
                      bottom: h + 3,
                      child: _bubble(kcal, over: kcal > data.target),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// screens.css:414-433：over 规则(433)在 today 规则(429)之后 → over+today 时
  /// 纯色 warnSoft 覆盖渐变（CSS 后者胜出，bug-for-bug 保留）。
  BoxDecoration _barDecoration(int i, int kcal) {
    final radius = const BorderRadius.only(
      topLeft: Radius.circular(7),
      topRight: Radius.circular(7),
      bottomLeft: Radius.circular(3),
      bottomRight: Radius.circular(3),
    );
    if (kcal > data.target) {
      return BoxDecoration(color: Tokens.warnSoft, borderRadius: radius);
    }
    if (i == todayIndex) {
      return BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Tokens.primary, Tokens.primaryDeep]), // 180deg
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
              color: Tokens.primaryGlow,
              blurRadius: 12,
              offset: Offset(0, 4),
              spreadRadius: -4), // 0 4px 12px -4px var(--primary-glow)
        ],
      );
    }
    return BoxDecoration(color: Tokens.primarySoft, borderRadius: radius);
  }

  /// 气泡：surface 底 + hairline 描边 + 6px 圆角，字色 over→warn 否则 primaryDeep
  Widget _bubble(int kcal, {required bool over}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Tokens.surface,
        border: Border.all(color: Tokens.hairline),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [Tokens.shadowBarVal],
      ),
      child: Text(
        kcal > 0 ? '$kcal kcal' : '未记录', // app.js:798
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: over ? Tokens.warn : Tokens.primaryDeep,
        ),
      ),
    );
  }

  /// 标签：今天→'今天'（primary 加粗），否则 labels[i]（ink3）
  Widget _label(int i) {
    final isToday = i == todayIndex;
    return Text(
      isToday ? '今天' : data.labels[i], // app.js:799
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: Tokens.textXs, // .lbl 11px
        color: isToday ? Tokens.primary : Tokens.ink3,
        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }

  /// 目标虚线：1.5px dashed warn + 右端上移标签（.target-line span top:-16 right:0）
  Widget _targetLine() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: double.infinity,
          height: 1.5,
          child: CustomPaint(painter: _DashedLinePainter(Tokens.warn)),
        ),
        Positioned(
          right: 0,
          top: -16, // screens.css:412 .target-line span top:-16px（T8 缓办 D②：原 -14）
          child: Text(
            '目标 ${data.target}',
            style: const TextStyle(
                fontSize: 10, color: Tokens.warn, height: 1.2),
          ),
        ),
      ],
    );
  }
}

/// CSS dashed border 浏览器实现不统一，这里取 6/4 节距、1.5 粗细同色。
class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dash = 6.0, gap = 4.0;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, y),
          Offset(math.min(x + dash, size.width), y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
