// ShiguangFlutter/lib/features/home/steps_card.dart
// 首页步数卡：展示所选日期的步数、距离与活动热量，附最近 7 天迷你柱。
// 数据源 = 小米云每日活动缓存（miDailyActivityProvider，分钟切片按天聚合）。
// 版式参考本地组件库 boardui/stat-cards（KPI 值 + 趋势条），按食光令牌落地。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/mi_cloud_client.dart' show MiDailyActivity;
import '../../data/mi_daily_activity_store.dart' show miDailyActivityProvider;

class StepsCard extends ConsumerWidget {
  const StepsCard({super.key, required this.date});

  /// 所选日期（YYYY-MM-DD）。
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(miDailyActivityProvider).maybeWhen(
          data: (m) => m,
          orElse: () => const <String, MiDailyActivity>{},
        );
    final today = daily[date];
    final week = _weekWindow(date, daily);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Tokens.sp5),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        boxShadow: Tokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('步数',
                  style: TextStyle(
                      fontSize: Tokens.textMd,
                      fontWeight: FontWeight.w700,
                      color: Tokens.ink)),
              const Spacer(),
              Text('最近 7 天',
                  style: TextStyle(
                      fontSize: Tokens.textXs, color: Tokens.ink3)),
            ],
          ),
          const SizedBox(height: Tokens.sp2),
          if (today == null || today.steps <= 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Tokens.sp2),
              child: Text('同步手环后显示步数与活动',
                  style: TextStyle(
                      fontSize: Tokens.textSm, color: Tokens.ink2)),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_thousands(today.steps),
                    style: const TextStyle(
                        fontSize: 34,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        color: Tokens.ink)),
                const SizedBox(width: Tokens.sp1),
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Text('步',
                      style: TextStyle(
                          fontSize: Tokens.textSm, color: Tokens.ink3)),
                ),
              ],
            ),
            const SizedBox(height: Tokens.sp1),
            Text(
              '≈ ${(today.distanceM / 1000).toStringAsFixed(1)} km · 活动 ${today.activeKcal.round()} kcal',
              style: const TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2),
            ),
          ],
          const SizedBox(height: Tokens.sp3),
          _WeekBars(week: week),
        ],
      ),
    );
  }

  /// 以 [date] 为最后一天，向前取 7 天（缺失日留空柱）。
  static List<({String date, String label, int steps, bool current})> _weekWindow(
      String date, Map<String, MiDailyActivity> daily) {
    final d = DateTime.tryParse(date) ?? DateTime.now();
    return [
      for (var i = 6; i >= 0; i--)
        () {
          final t = DateTime(d.year, d.month, d.day - i);
          final iso = '${t.year}-'
              '${t.month.toString().padLeft(2, '0')}-'
              '${t.day.toString().padLeft(2, '0')}';
          return (
            date: iso,
            label: i == 0 ? '今' : '${t.day}',
            steps: daily[iso]?.steps ?? 0,
            current: i == 0,
          );
        }(),
    ];
  }

  static String _thousands(int n) {
    final s = '$n';
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.week});

  final List<({String date, String label, int steps, bool current})> week;

  @override
  Widget build(BuildContext context) {
    final maxSteps =
        week.fold<int>(0, (a, d) => d.steps > a ? d.steps : a);
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in week)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: maxSteps == 0
                        ? 4
                        : 4 + 32 * (d.steps / maxSteps),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: d.current
                          ? Tokens.primary
                          : (d.steps > 0
                              ? Tokens.primarySoft
                              : Tokens.surfaceSoft),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: Tokens.sp1),
                  Text(d.label,
                      style: TextStyle(
                          fontSize: Tokens.textXs,
                          color: d.current ? Tokens.ink2 : Tokens.ink3)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
