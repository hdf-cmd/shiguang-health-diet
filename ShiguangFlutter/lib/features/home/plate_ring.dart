// ShiguangFlutter/lib/features/home/plate_ring.dart
// 首页营养餐盘环（M3 Task 7）。唯一事实源：js/app.js:296-344 renderRing +
// index.html:77-94（SVG 结构/中心文案）+ css/screens.css:151-161（168×168、
// #ring-kcal drop-shadow）。
//
// SVG→Flutter 等价换算：
// - SVG 整体 CSS rotate(-90deg)（screens.css:152）⇒ Flutter 起笔角统一 -π/2
//   （12 点方向），正 sweepAngle 即顺时针，与 SVG circle 路径顺时针方向一致；
// - 外环 dashoffset = C_OUT*(1-pct) ⇒ 扫角 = pct*2π（C_OUT=2π·78 约掉）；
// - 内环三段 strokeDasharray=`len C_IN` + strokeDashoffset=-前段累加
//   （app.js:332-338）⇒ 每段起点 = 前段扫角之和，顺排不重叠。
//
// 运动消耗：exerciseKcal 恒 0——运动打卡不在 M3，**M4+ 接运动打卡后启用**
// （H5 app.js:298-299 budget = target + exerciseKcal 的 ex 项）。
import 'dart:math' as math;

import 'package:flutter/material.dart'; // visibleForTesting 经 material 再导出

import '../../app/theme.dart';

/// 内环三段色序 [carb, protein, fat]（index.html:83-88 / app.js:326-338 segs
/// 数组顺序，与 macroFractions 返回顺序一一对应，**不得调换**）。
/// T8 缓办 C：提到文件级供测试锁色序（此前调换 segColors 全测试仍绿）。
@visibleForTesting
const List<Color> plateRingSegColors = [
  Tokens.nutCarb,
  Tokens.nutProtein,
  Tokens.nutFat,
];

/// 外环扫角比例（app.js:314 `pct = Math.min(1, s.kcal / budget)`）。
/// budget=0 防除零（锁定语义，bug-for-bug 对齐浏览器）：
/// kcal=0 时 H5 为 0/0=NaN → dashoffset 无效样式 → 保持初始满 offset（扫角 0）；
/// kcal>0 时 x/0=Infinity → min(1,∞)=1 满环。
double ringSweep(int kcal, int budget) {
  if (budget <= 0) return kcal > 0 ? 1 : 0;
  final pct = kcal / budget;
  return pct > 1 ? 1 : pct.toDouble();
}

/// 内环三段占比 [carb, protein, fat]（app.js:326-331）。
/// 分母 `totals = carb + protein + fat || 1`：全 0 时分母按 1 → 三段皆 0。
/// **顺序不得换**（H5 segs 数组 carb→protein→fat，色一一对应）。
List<double> macroFractions(int carb, int protein, int fat) {
  final totals = carb + protein + fat == 0 ? 1 : carb + protein + fat;
  return [carb / totals, protein / totals, fat / totals];
}

/// 外环进度色（app.js:323 `s.kcal > budget ? 'var(--warn)' : 'var(--primary)'`）。
/// 严格大于才变 warn：恰好等于预算仍是 primary。
Color ringProgressColor(int kcal, int budget) =>
    kcal > budget ? Tokens.warn : Tokens.primary;

/// 营养餐盘环：168×168（screens.css:151），外环热量进度 + 内环三大营养素配比，
/// 中心显 `max(0, budget-kcal)`「还可摄入 kcal」（app.js:300/324 + index.html:90-93）。
class PlateRing extends StatelessWidget {
  const PlateRing({
    super.key,
    required this.kcal,
    required this.target,
    required this.carb,
    required this.protein,
    required this.fat,
  });

  final int kcal;

  /// 云函数派生的基准目标（契约 dailySummary.target，端上不硬编码）
  final int target;
  final int carb;
  final int protein;
  final int fat;

  /// 运动消耗恒 0：运动打卡不在 M3，**M4+ 接运动打卡后启用**（届时 budget
  /// = target + exerciseKcal 的加项生效，H5 app.js:298-299 同源）。
  static const int exerciseKcal = 0;

  /// 今日额度 = 基准目标 + 运动消耗（app.js:299）
  int get budget => target + exerciseKcal;

  /// 还可摄入 = max(0, budget - kcal)（app.js:300，负值夹 0）
  int get remain => math.max(0, budget - kcal);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 外环进度：H5 anime dashoffset 600ms outCubic（app.js:317-319，
          // 注意这是 anime 的贝塞尔(0.215,.61,.355,1)，与 design-tokens
          // --ease-out 不同缓动，勿与柱入场动画混用）。begin=0 ⇔ SVG
          // 初始 dashoffset=490（空环），首帧起扫。
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: ringSweep(kcal, budget)),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, sweep, _) => CustomPaint(
              size: const Size(_size, _size),
              painter: _PlateRingPainter(
                sweep: sweep,
                progressColor: ringProgressColor(kcal, budget),
                fractions: macroFractions(carb, protein, fat),
              ),
            ),
          ),
          // 中心：数字滚动 500ms outCubic、逐帧取整（app.js:324 animateNum
          // →380-387 `Math.round(proxy.v)`；IntTween 每帧 lerp 后 round() 等价；
          // begin=0 ⇔ H5 静态初值 "0"）
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: remain),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  '$value',
                  key: const ValueKey('ring-num'),
                  style: const TextStyle(
                      fontSize: Tokens.textNum,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      color: Tokens.ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                      letterSpacing: -0.9), // --ls -.02em × 46px
                ),
              ),
              const SizedBox(height: 2), // .center gap: 2px（screens.css:155）
              const Text('还可摄入 kcal',
                  style: TextStyle(
                      fontSize: Tokens.textXs, color: Tokens.ink3)),
            ],
          ),
        ],
      ),
    );
  }

  static const double _size = 168; // .plate-ring 168×168（screens.css:151）
  static const double _c = _size / 2; // SVG cx/cy=84
  static const double _rOut = 78, _wOut = 7; // index.html:79-81
  static const double _rIn = 62, _wIn = 15; // index.html:82-88
}

class _PlateRingPainter extends CustomPainter {
  const _PlateRingPainter({
    required this.sweep,
    required this.progressColor,
    required this.fractions,
  });

  /// 外环进度扫角比例 0..1（动画中间值）
  final double sweep;
  final Color progressColor;
  final List<double> fractions;

  static const Offset _center = Offset(PlateRing._c, PlateRing._c);
  static const double _startAngle = -math.pi / 2; // ⇔ SVG rotate(-90deg)
  static const double _fullTurn = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    // 外环底轨（index.html:79：r=78 stroke=--line 宽 7）
    canvas.drawCircle(_center, PlateRing._rOut, _stroke(PlateRing._wOut, Tokens.line));
    // 外环进度弧（index.html:80-81：宽 7 linecap=round；
    // #ring-kcal filter: drop-shadow(0 3px 8px --primary-glow)，screens.css:161）。
    // Flutter Paint 无 shadow 属性 → 先画一条偏移 (0,3)、MaskFilter 模糊
    // （CSS blur 8px ≈ sigma 4）的 primaryGlow 辉光弧，再叠主弧，视觉等价。
    // 扫角 0 时跳过：round cap 会把零角弧画成圆点，SVG 空 dash 不绘制。
    if (sweep > 0) {
      final arcRect =
          Rect.fromCircle(center: _center, radius: PlateRing._rOut);
      final glow = _stroke(PlateRing._wOut, Tokens.primaryGlow)
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawArc(arcRect.shift(const Offset(0, 3)), _startAngle,
          _fullTurn * sweep, false, glow);
      canvas.drawArc(
        arcRect,
        _startAngle,
        _fullTurn * sweep,
        false,
        _stroke(PlateRing._wOut, progressColor)
          ..strokeCap = StrokeCap.round,
      );
    }
    // 内环底轨（index.html:82：r=62 stroke=--surface-soft 宽 15）
    canvas.drawCircle(_center, PlateRing._rIn, _stroke(PlateRing._wIn, Tokens.surfaceSoft));
    // 内环三段（index.html:83-88 顺序 carb→protein→fat，色 nut-*；app.js:332-338
    // 负 offset 顺排 ⇔ 起点=前段累加）；色序与 fractions 下标配对见
    // plateRingSegColors（文件级常量，测试已锁）
    var angle = _startAngle;
    for (var i = 0; i < 3; i++) {
      final f = fractions[i];
      if (f <= 0) continue;
      canvas.drawArc(
        Rect.fromCircle(center: _center, radius: PlateRing._rIn),
        angle,
        _fullTurn * f,
        false,
        _stroke(PlateRing._wIn, plateRingSegColors[i]),
      );
      angle += _fullTurn * f;
    }
  }

  Paint _stroke(double width, Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..color = color
    ..isAntiAlias = true;

  @override
  bool shouldRepaint(_PlateRingPainter old) =>
      old.sweep != sweep ||
      old.progressColor != progressColor ||
      old.fractions[0] != fractions[0] ||
      old.fractions[1] != fractions[1] ||
      old.fractions[2] != fractions[2];
}
