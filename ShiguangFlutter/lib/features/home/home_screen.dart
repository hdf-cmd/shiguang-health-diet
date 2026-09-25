// ShiguangFlutter/lib/features/home/home_screen.dart
// 首页（M2 Task 8：接真实数据）。原 M1 静态版 home_static_screen.dart 演进而来。
// 数据源：home_controller.dart 的 summaryProvider/recordsProvider（date=todayProvider）。
// H5 行为对照 js/app.js:1926-1931（refresh 先拉 summary 再渲染）、js/app.js:595（记录拉取）；
// 目标值恒取云函数 summary.target（契约 dailySummary.target，M1 硬编码 1975 清除——M1 终审 I1）。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/models.dart';
import 'home_controller.dart';

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
            _ringCard(summary.value),
            const SizedBox(height: Tokens.sp3),
            _mealsCard(records.value ?? const []),
          ],
        ],
      ),
    );
  }

  /// 热量环卡：中心=已摄入 kcal，右侧「已摄入 / 目标」；进度 = kcal/target 封顶 1
  Widget _ringCard(Summary? s) {
    final pct = (s == null || s.target <= 0)
        ? 0.0
        : math.min(s.kcal / s.target, 1.0).toDouble();
    return _card(
      color: Tokens.primaryDeep,
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 104,
                  height: 104,
                  child: CircularProgressIndicator(
                      value: pct,
                      strokeWidth: 10,
                      color: Colors.white38,
                      backgroundColor: Colors.white12),
                ),
                Text(s == null ? '—' : _n(s.kcal),
                    style: const TextStyle(
                        fontSize: Tokens.textNum,
                        color: Colors.white,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: Tokens.sp4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('已摄入 / 目标',
                    style: TextStyle(color: Colors.white70, fontSize: Tokens.textSm)),
                const SizedBox(height: Tokens.sp1),
                Text(
                  s == null ? '— / — kcal' : '${_n(s.kcal)} / ${_n(s.target)} kcal',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: Tokens.textLg,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 三餐卡：早餐/午餐/晚餐各行，真实记录渲染「名（portion）… kcal」，空则「未记录」
  Widget _mealsCard(List<Map<String, dynamic>> list) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('三餐记录', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: Tokens.sp3),
          for (final (label, meal) in const [('早餐', 'breakfast'), ('午餐', 'lunch'), ('晚餐', 'dinner')])
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
