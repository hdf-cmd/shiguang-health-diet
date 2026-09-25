// ShiguangFlutter/lib/features/home/home_screen.dart
// 首页（M2 Task 8：接真实数据；M3 Task 7：餐盘环 + 加载/空态区分）。
// 原 M1 静态版 home_static_screen.dart 演进而来。
// 数据源：home_controller.dart 的 summaryProvider/recordsProvider（date=todayProvider）。
// H5 行为对照 js/app.js:1926-1931（refresh 先拉 summary 再渲染）、js/app.js:595（记录拉取）；
// 目标值恒取云函数 summary.target（契约 dailySummary.target，M1 硬编码 1975 清除——M1 终审 I1）。
// M3-T7（终审 Minor M1 核销）：加载期显式静态骨架（plate-ring-skeleton /
// meal-skeleton，与报告页 T4 卡框骨架同路线——不排持续帧，pumpAndSettle 不死等），
// 仅"加载完成且无记录"才显零值态；餐盘环本体见 plate_ring.dart。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/models.dart';
import 'home_controller.dart';
import 'plate_ring.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// 数展示：与 H5 一致按整数呈现（Math.round 语义）
  static String _n(num v) => '${v.round()}';

  /// error 态文案：ApiException 露后端 message（H5 err.textContent = e.message 语义），
  /// 其余异常给通用兜底。两个请求任一失败即整体进 error 卡。
  static String? _errorMessage(AsyncValue<Object?> a, AsyncValue<Object?> b) {
    final err = a.hasError ? a.error : (b.hasError ? b.error : null);
    if (err == null) return null;
    return err is ApiException ? err.message : '加载失败，请检查网络后重试';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(todayProvider);
    final summary = ref.watch(summaryProvider(date));
    final records = ref.watch(recordsProvider(date));
    final error = _errorMessage(summary, records);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Tokens.sp4),
        children: [
          const Text('今日盘子',
              style: TextStyle(
                  fontSize: Tokens.textXl,
                  fontWeight: FontWeight.w800,
                  color: Tokens.ink)),
          const SizedBox(height: Tokens.sp4),
          if (error != null)
            _card(
              color: Tokens.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(error,
                      style: const TextStyle(
                          color: Tokens.danger, fontSize: Tokens.textMd)),
                  const SizedBox(height: Tokens.sp2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        // 重试 = invalidate 两个 provider 重新取数（非本地翻牌）
                        ref.invalidate(summaryProvider(date));
                        ref.invalidate(recordsProvider(date));
                      },
                      child: const Text('重试'),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _plateCard(summary),
            const SizedBox(height: Tokens.sp3),
            _mealsCard(records),
          ],
        ],
      ),
    );
  }

  /// 餐盘卡（index.html:70-104 .card.plate-card，surface 白底——M2 深色占位卡
  /// 替换之）。结构 = .plate-top（左环右 aside，screens.css:150）+ nutrient-note
  /// （index.html:103）。plate-head 日期导航 ‹ 今天 › 与卡内营养素条不在本期
  /// （板块日期切换非 M3 范围）。
  /// 加载期（summary 未回）：环位显静态骨架、aside 数字显"—"——与"加载完成
  /// 且无记录"的零值态（真实 0/预算数字）可分辨（M2 终审 Minor M1）。
  Widget _plateCard(AsyncValue<Summary> summary) {
    final s = summary.value;
    // H5 renderRing 入参先 Math.round 语义取整（本仓 _n 口径同源）
    final kcal = s?.kcal.round() ?? 0;
    final target = s?.target.round() ?? 0;
    final ring = s == null
        ? _PlateRingSkeleton()
        : PlateRing(
            kcal: kcal,
            target: target,
            carb: s.carb.round(),
            protein: s.protein.round(),
            fat: s.fat.round(),
          );
    final budget = s == null ? '—' : '${target + PlateRing.exerciseKcal}';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ring,
              const SizedBox(width: Tokens.sp5), // .plate-top gap --sp-5
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _goalLine('今日额度', budget),
                    const SizedBox(height: Tokens.sp3), // .aside gap --sp-3
                    _goalLine('已摄入', s == null ? '—' : '$kcal'),
                    const SizedBox(height: Tokens.sp3),
                    _goalLine('运动消耗', s == null ? '—' : '0'),
                    // note（app.js:306-308 ex==0 分支逐字；ex=0 恒走此分支，
                    // ex>0 文案归 M4+ 运动打卡）。加载期无 target 不显。
                    if (s != null) ...[
                      const SizedBox(height: Tokens.sp2), // .goal-note margin-top
                      Text(
                        key: const ValueKey('ring-note'),
                        '基准目标 $target kcal · 记运动后额度自动上调',
                        style: const TextStyle(
                            fontSize: Tokens.textXs,
                            color: Tokens.ink3,
                            height: 1.6), // line-height 1.6
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // 营养素口径标注（app.js:310-311 逐字；nutrient-note 在 index.html:103
          // 餐盘卡内 → 逐字搬；margin-top --sp-4 由卡内间距承担）
          if (s != null)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.sp4),
              child: Text(
                key: const ValueKey('nutrient-note'),
                '营养素目标 = 基准 $target × 供能比 50%/25%/25% ÷ (4/4/9) kcal，'
                '不含运动额度；热量额度含运动，两者基数不同',
                style: const TextStyle(
                    fontSize: Tokens.textXs, color: Tokens.ink3, height: 1.6),
              ),
            ),
        ],
      ),
    );
  }

  /// .goal-line（screens.css:164-165）：`标签 数字 kcal`，数字 b 语义
  /// （ink 色 w600 tabular-nums）
  Widget _goalLine(String label, String value) {
    return Text.rich(TextSpan(
      style: const TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2),
      children: [
        TextSpan(text: '$label '),
        TextSpan(
          style: const TextStyle(
              color: Tokens.ink,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()]),
          text: value,
        ),
        const TextSpan(text: ' kcal'),
      ],
    ));
  }

  /// 三餐卡：早餐/午餐/晚餐各行，真实记录渲染「名（portion）… kcal」，空则「未记录」。
  /// 加载期（records 未回）显静态骨架行（meal-skeleton），不伪装「未记录」零值态
  /// （M2 终审 Minor M1，与餐盘卡同口径）。
  Widget _mealsCard(AsyncValue<List<Map<String, dynamic>>> records) {
    final list = records.value;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('三餐记录', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: Tokens.sp3),
          if (list == null)
            const Column(
              key: ValueKey('meal-skeleton'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MealSkeletonRow(),
                _MealSkeletonRow(),
                _MealSkeletonRow(),
              ],
            )
          else
            for (final (label, meal) in const [
              ('早餐', 'breakfast'),
              ('午餐', 'lunch'),
              ('晚餐', 'dinner')
            ])
              _mealRow(label, _recordsOf(list, meal)),
        ],
      ),
    );
  }

  static List<Map<String, dynamic>> _recordsOf(List<Map<String, dynamic>> list, String meal) =>
      list.where((r) => r['meal'] == meal).toList(growable: false);

  Widget _mealRow(String label, List<Map<String, dynamic>> recs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.sp2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style: const TextStyle(color: Tokens.ink2, fontSize: Tokens.textSm)),
          ),
          Expanded(
            child: recs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: Tokens.sp1),
                    child: Text('未记录',
                        style: TextStyle(color: Tokens.ink3, fontSize: Tokens.textSm)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in recs)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: Tokens.sp1),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${r['name'] ?? ''}（${r['portion'] ?? ''}）',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Tokens.ink, fontSize: Tokens.textSm),
                                ),
                              ),
                              const SizedBox(width: Tokens.sp2),
                              Text(
                                '${_n((r['kcal'] as num?) ?? 0)} kcal',
                                style: const TextStyle(
                                    color: Tokens.ink2,
                                    fontSize: Tokens.textSm,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child, Color? color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Tokens.sp5),
      decoration: BoxDecoration(
        color: color ?? Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        boxShadow: Tokens.shadowCard,
      ),
      child: child,
    );
  }
}

/// 加载期餐盘环占位：168×168 空环底轨几何（Tokens.line 描边）+「加载中」。
/// 纯静态不排持续帧——对齐报告页 T4 卡框骨架路线（无限 CircularProgressIndicator
/// + pumpAndSettle 死等的教训，见 report_screen.dart:115-128 注释）。
class _PlateRingSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('plate-ring-skeleton'),
      width: 168,
      height: 168,
      child: Center(
        child: Container(
          width: 154, // ≈ 外环中线直径 156（r78±w7/2）取整描边占位
          height: 154,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Tokens.line, width: 7),
          ),
          child: const Center(
            child: Text('加载中',
                style: TextStyle(fontSize: Tokens.textXs, color: Tokens.ink3)),
          ),
        ),
      ),
    );
  }
}

/// 加载期三餐骨架行：标签位 + 灰条占位（高 ≈ textSm 行，surfaceSoft）
class _MealSkeletonRow extends StatelessWidget {
  const _MealSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: Tokens.sp2),
      child: Row(
        children: [
          SizedBox(width: 44), // 标签位列宽（_mealRow 同宽）
          SizedBox(width: Tokens.sp2),
          Expanded(
            child: SizedBox(
              height: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Tokens.surfaceSoft,
                  borderRadius: BorderRadius.all(Radius.circular(Tokens.radiusSm)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
