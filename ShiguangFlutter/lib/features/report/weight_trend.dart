// ShiguangFlutter/lib/features/report/weight_trend.dart
// 体重趋势线（M3 Task 6）。逐字移植 H5 js/app.js:845-905 renderWeightTrend ——
// 那张 SVG（index.html:172 viewBox="0 0 320 132"）里的每一条线、每一个点、
// 每一段文字都在这里按同一套常数重画：
//   绘图区  X0=44 X1=306 Y0=16 Y1=104（app.js:864，左 36 放刻度、底 24 放日期）
//   值域    hi/lo 外扩到最小跨度 1kg，再 0.5 对齐取整（app.js:859-861）
//   映射    xOf(n==1 居中)/yOf 翻转（app.js:865-866）
//   网格    4 条等分，末条实线其余 dash "3 4"，刻度右对齐 9 号 ink-3（869-874）
//   面积    折线 + 末点垂 Y1 + 首点垂 Y1 闭合，primary 8% 不透明（879,896）
//   折线    primary 2.5 圆角端点/连接（898）
//   圆点    末点 r4.2 实心，其余 r3 白底 primary 描边 1.8（887）
//   数值    点上方 8px、9.5 号 600，末点 primary-deep 其余 ink-2，首末改锚点（884-888）
//   日期    labels[i] 缺项则不画（892-893）
//   delta   当前 jsNumText(末值) · 本周 toFixed(2)（带 + 仅当 >0），降/平 primary、升 warn
// 画布按 size.width/320 整体缩放，等价 SVG 的 preserveAspectRatio：线宽/字号同比放大。
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/js_compat.dart' show jsNumText;

/// viewBox 与绘图区常数（改这里等于改 H5 的 SVG 几何，必须同步 app.js:864）
abstract final class TrendGeometry {
  static const double viewWidth = 320;
  static const double viewHeight = 132;
  static const double x0 = 44, x1 = 306, y0 = 16, y1 = 104;

  /// 网格 dash 节距：stroke-dasharray="3 4"（app.js:873）
  static const double dashOn = 3, dashOff = 4;
}

/// 数值标签的水平锚点，对应 SVG text-anchor（app.js:885）
enum TrendLabelAnchor { start, middle, end }

/// 一条 Y 网格线：y 坐标、刻度值、是否虚线（末条 = lo = 底边实线，app.js:873）
class TrendGridLine {
  const TrendGridLine(
      {required this.y, required this.value, required this.dashed});

  final double y;
  final double value;
  final bool dashed;
}

/// 一个数据点：圆心、显示值（原始点值，非 0.5 对齐后的值）、半径、首尾语义
class TrendDot {
  const TrendDot({
    required this.center,
    required this.value,
    required this.radius,
    required this.isLast,
    required this.anchor,
    required this.labelDx,
  });

  final Offset center;
  final double value;
  final double radius;
  final bool isLast;

  /// 数值标签锚点：非单点时首 start / 末 end / 其余 middle（app.js:885）
  final TrendLabelAnchor anchor;

  /// 锚点微移：首 -1、末 +1、其余 0（app.js:886）
  final double labelDx;
}

/// 纯几何结果：不含颜色与文案，坐标一律用 viewBox 单位（0-320 / 0-132）
class TrendLayout {
  const TrendLayout({
    required this.values,
    required this.points,
    required this.dots,
    required this.grid,
    required this.lo,
    required this.hi,
    required this.single,
  });

  /// 参与绘图的点值序列（单点时长度 1，其余同原始 points）
  final List<double> values;
  final List<Offset> points;
  final List<TrendDot> dots;
  final List<TrendGridLine> grid;
  final double lo, hi;

  /// 只有一天数据：画居中单点，不复制成两端两点（app.js:854 注释的语义）
  final bool single;

  int get count => points.length;

  /// 面积多边形的顶点 = 折线点 + 末点垂到 Y1 + 首点垂到 Y1（app.js:879）
  List<Offset> get areaPoints => <Offset>[
        ...points,
        Offset(points.last.dx, TrendGeometry.y1),
        Offset(points.first.dx, TrendGeometry.y1),
      ];
}

/// xOf：n==1 时居中，否则在 [X0,X1] 均分（app.js:865，n-1 除零由 single 特判兜住）
double trendXOf(int i, int n) => n == 1
    ? (TrendGeometry.x0 + TrendGeometry.x1) / 2
    : TrendGeometry.x0 + i * (TrendGeometry.x1 - TrendGeometry.x0) / (n - 1);

/// yOf：值 → 屏幕 y（翻转，hi 贴 Y0、lo 贴 Y1）（app.js:866）
double trendYOf(double v, double lo, double hi) =>
    TrendGeometry.y1 - (v - lo) / (hi - lo) * (TrendGeometry.y1 - TrendGeometry.y0);

/// 几何布局。空数据返回 null —— 对齐 app.js:847-851 的提前 return（只画占位文字）。
TrendLayout? computeTrendLayout(List<double> points) {
  if (points.isEmpty) return null;
  final raw = points;
  final single = raw.length == 1;
  final pts0 = single ? <double>[raw.first] : raw;
  final n = pts0.length;

  // 值域：最小可视跨度 1kg（微波动不至于放大成过山车），刻度 0.5 对齐
  var hi = pts0.reduce(math.max), lo = pts0.reduce(math.min);
  if (hi - lo < 1) {
    final c = (hi + lo) / 2;
    hi = c + 0.5;
    lo = c - 0.5;
  }
  hi = (hi * 2).ceilToDouble() / 2;
  lo = (lo * 2).floorToDouble() / 2;

  final pts = <Offset>[
    for (var i = 0; i < n; i++)
      Offset(trendXOf(i, n), trendYOf(pts0[i], lo, hi)),
  ];
  final step = (hi - lo) / 3;
  final grid = <TrendGridLine>[
    for (var i = 0; i < 4; i++)
      TrendGridLine(
          y: trendYOf(hi - step * i, lo, hi),
          value: hi - step * i,
          dashed: i != 3),
  ];
  final dots = <TrendDot>[
    for (var i = 0; i < n; i++)
      TrendDot(
        center: pts[i],
        // 数值取原始点（app.js:884 raw[min(i, len-1)]，单点即 raw[0]）
        value: raw[math.min(i, raw.length - 1)],
        radius: i == n - 1 ? 4.2 : 3.0,
        isLast: i == n - 1,
        anchor: i == 0 && !single
            ? TrendLabelAnchor.start
            : (i == n - 1 && !single)
                ? TrendLabelAnchor.end
                : TrendLabelAnchor.middle,
        labelDx: i == 0 && !single ? -1.0 : (i == n - 1 && !single ? 1.0 : 0.0),
      ),
  ];
  return TrendLayout(
      values: pts0, points: pts, dots: dots, grid: grid, lo: lo, hi: hi, single: single);
}

/// 末值-首值，按 JS `.toFixed(2)` 再回读成数字（app.js:902）。
/// 回读这一步是必要的：H5 拿字符串和 0 比（`delta > 0`、`delta <= 0`），
/// "0.00"/"-0.00" 会被隐式转数成 0 → 既不加 + 也不变橙。
/// 体重精度只有两位小数，不会出现 x.xx5 平局，Dart toStringAsFixed 与 V8
/// toFixed 的舍入差异在真实数据上不可见。
double? weightDeltaRounded(List<double> points) =>
    points.isEmpty ? null : double.parse((points.last - points.first).toStringAsFixed(2));

/// #weight-delta 文案（app.js:903）：`当前 ${raw.at(-1)} kg · 本周 ${+?}${delta} kg`。
/// 「当前」用末值原样（JS 模板字符串语义 → jsNumText，整数不带 .0），delta 固定两位。
/// 空数据返回空串（app.js:849）。区间切月/周不改文案：H5 也叫"本周"。
String weightDeltaText(List<double> points) {
  if (points.isEmpty) return '';
  final delta = (points.last - points.first).toStringAsFixed(2);
  final signed = double.parse(delta);
  return '当前 ${jsNumText(points.last)} kg · '
      '本周 ${signed > 0 ? '+' : ''}$delta kg';
}

/// delta 行颜色（app.js:904）：降/平 → primary，升 → warn；空态退回 .more 的 ink-3
Color weightDeltaColor(List<double> points) {
  final signed = weightDeltaRounded(points);
  if (signed == null) return Tokens.ink3;
  return signed <= 0 ? Tokens.primary : Tokens.warn;
}

/// 契约 weightTrend 返回体 → 视图模型（{points:[num], labels:[String]}）。
/// points 缺失/非数组按空数据走占位分支（等价 app.js:847 `!w.points`）。
/// 解析放 features 层：domain/report.dart 是 T3 冻结产物，本任务不改 domain。
class WeightTrend {
  const WeightTrend({required this.points, required this.labels});

  final List<double> points;
  final List<String> labels;

  factory WeightTrend.fromMap(Map<String, dynamic> m) {
    final rawPoints = m['points'];
    final rawLabels = m['labels'];
    return WeightTrend(
      points: rawPoints is List
          ? <double>[for (final v in rawPoints) (v as num).toDouble()]
          : const <double>[],
      // labels 缺项/空串都不画该日期（app.js:892 `labels[i] ? … : ''`）
      labels: rawLabels is List
          ? <String>[for (final v in rawLabels) v?.toString() ?? '']
          : const <String>[],
    );
  }
}

/// 体重趋势图：AspectRatio(320/132) 保住 SVG viewBox 比例（css/screens.css:440
/// `svg{width:100%;height:auto}` 的等价形），空数据只画居中占位文字。
class WeightTrendChart extends StatelessWidget {
  const WeightTrendChart(
      {super.key, required this.points, this.labels = const <String>[]});

  final List<double> points;
  final List<String> labels;

  static const Key frameKey = ValueKey<String>('weight-trend-frame');
  static const Key canvasKey = ValueKey<String>('weight-trend-canvas');

  @override
  Widget build(BuildContext context) {
    final layout = computeTrendLayout(points);
    return AspectRatio(
      key: frameKey,
      aspectRatio: TrendGeometry.viewWidth / TrendGeometry.viewHeight,
      child: layout == null
          ? const Center(
              child: Text('暂无体重数据', // app.js:848 逐字，字号 13 = Tokens.textSm
                  style: TextStyle(
                      fontSize: Tokens.textSm,
                      fontWeight: FontWeight.w400,
                      color: Tokens.ink3)),
            )
          : CustomPaint(
              key: canvasKey,
              painter: _WeightTrendPainter(layout: layout, labels: labels),
            ),
    );
  }
}

class _WeightTrendPainter extends CustomPainter {
  _WeightTrendPainter({required this.layout, required this.labels});

  final TrendLayout layout;
  final List<String> labels;

  static const double _x0 = TrendGeometry.x0,
      _x1 = TrendGeometry.x1,
      _y1 = TrendGeometry.y1;

  @override
  void paint(Canvas canvas, Size size) {
    // SVG preserveAspectRatio：整体等比缩放，线宽与字号跟着走（app.js 侧 viewBox 语义）
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / TrendGeometry.viewWidth);

    // 绘制顺序同 app.js:895-900 的 innerHTML：面积 → 网格 → 折线 → 圆点/数值 → 日期
    final area = Path();
    final areaPts = layout.areaPoints;
    area.moveTo(areaPts.first.dx, areaPts.first.dy);
    for (final p in areaPts.skip(1)) {
      area.lineTo(p.dx, p.dy);
    }
    area.close();
    canvas.drawPath(
        area,
        Paint()
          ..color = Tokens.primary.withValues(alpha: 0.08) // opacity="0.08"
          ..style = PaintingStyle.fill);

    for (final g in layout.grid) {
      _hLine(canvas, g.y,
          color: Tokens.line, width: 0.7, dashed: g.dashed, text: g.value);
    }

    final line = Path()
      ..moveTo(layout.points.first.dx, layout.points.first.dy);
    for (final p in layout.points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        line,
        Paint()
          ..color = Tokens.primary
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round // stroke-linecap/linejoin="round"
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke);

    for (final d in layout.dots) {
      canvas.drawCircle(
          d.center,
          d.radius,
          Paint()
            ..color = d.isLast ? Tokens.primary : Tokens.surface // fill "#fff" → --surface
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          d.center,
          d.radius,
          Paint()
            ..color = Tokens.primary
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke);
      _text(canvas, d.value.toStringAsFixed(2),
          baselineY: d.center.dy - 8, // y = 点 y - 8
          anchorX: d.center.dx + d.labelDx,
          anchor: d.anchor,
          fontSize: 9.5,
          weight: FontWeight.w600,
          color: d.isLast ? Tokens.primaryDeep : Tokens.ink2);
    }

    for (var i = 0; i < layout.points.length; i++) {
      final lbl = i < labels.length ? labels[i] : '';
      if (lbl.isEmpty) continue; // labels 缺项不画该日期（app.js:892-893）
      _text(canvas, lbl,
          baselineY: _y1 + 16,
          anchorX: layout.points[i].dx,
          anchor: TrendLabelAnchor.middle,
          fontSize: 9.5,
          weight: FontWeight.w500,
          color: Tokens.ink2);
    }
  }

  /// 水平网格线 + 左侧刻度文字（刻度 x=X0-10、y=y+3、右对齐、9 号 ink-3）
  void _hLine(Canvas canvas, double y,
      {required Color color,
      required double width,
      required bool dashed,
      required double text}) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    if (dashed) {
      final period = TrendGeometry.dashOn + TrendGeometry.dashOff;
      for (var x = _x0; x < _x1; x += period) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + TrendGeometry.dashOn, _x1), y), paint);
      }
    } else {
      canvas.drawLine(Offset(_x0, y), Offset(_x1, y), paint);
    }
    _text(canvas, text.toStringAsFixed(1),
        baselineY: y + 3,
        anchorX: _x0 - 10,
        anchor: TrendLabelAnchor.end,
        fontSize: 9,
        weight: FontWeight.w400,
        color: Tokens.ink3);
  }

  /// SVG 文本语义：y 是基线，text-anchor 决定水平对齐
  void _text(Canvas canvas, String s,
      {required double baselineY,
      required double anchorX,
      required TrendLabelAnchor anchor,
      required double fontSize,
      required FontWeight weight,
      required Color color}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: fontSize, fontWeight: weight, color: color, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    final left = switch (anchor) {
      TrendLabelAnchor.start => anchorX,
      TrendLabelAnchor.middle => anchorX - tp.width / 2,
      TrendLabelAnchor.end => anchorX - tp.width,
    };
    final toBaseline =
        tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(canvas, Offset(left, baselineY - toBaseline));
  }

  @override
  bool shouldRepaint(_WeightTrendPainter oldDelegate) =>
      !identical(oldDelegate.layout, layout) ||
      !listEquals(oldDelegate.labels, labels);
}
