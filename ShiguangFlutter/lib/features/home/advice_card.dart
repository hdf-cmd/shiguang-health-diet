// ShiguangFlutter/lib/features/home/advice_card.dart
// 首页每日建议卡（M6-T5）。行为权威源 js/app.js:348-362 renderDailyAdvice：
// ctx 六入参同源装配，buildAdvice 最多 3 条 [emoji, 文案]。
// domain/advice.dart 已逐字移植（含 R2 >110 死分支），本文件纯接线。
// 卡容器/标题 ≙ index.html:106-109 .card.advice-home：标题实源「每日建议」+
// .more「根据今日记录实时生成」（简报推测「今日建议」，按实源，T4 先例）。
// li 行 ≙ app.js:361 `<li><span class=ai>{icon}</span><span>{text}</span></li>`
// → icon Text + 文案 Text。
// 不渲染语义 ≙ app.js:351 `if (!s) return`：summary 未就绪（在途/失败）整卡
// 不渲染。H5 加载期卡框可见系静态 HTML 占位（非渲染决策），Flutter 无骨架
// → 差异登记 task-5-report（简报②口径「卡位骨架/隐藏」取隐藏）。
// 装配源（六入参，逐一对 :352-359）：
//   summary      ← summaryProvider(date)（:349 state.summary）
//   exerciseKcal ← exerciseKcalProvider(date)（:354 state.exerciseKcal||0，
//                  provider 在途/失败 orElse 0 同义，T3 已接）
//   records      ← recordsProvider(date)（:355 state.records；在途 ≙ H5 初值 []）
//   isToday      ← date == todayIso()（:356）
//   weightKg     ← profileProvider body.weightKg ?? 55（:357 `||55`——上游裁定
//                  用 ??，0 值 falsy 支不引入，避 water_card T4 评审同类问题；
//                  在途/失败 → 55 ≙ H5 state.body 未就绪）
//   waterGoalMl  ← waterGoalMlOf(profileProvider)（:358 → app.js:1948
//                  `goal.waterMl || 1600` falsy 口径；M6-T7 F4 与 water_card
//                  收敛为 profile_providers.dart 单一工具）
// 版式 R4 自主：卡壳对齐首页既有卡（Tokens.surface 圆角阴影），标题行对齐
// 运动卡 .card-title + .more 结构。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/advice.dart' show buildAdvice, makeAdviceCtx;
import '../../domain/dates.dart' show todayIso;
import '../exercise/exercise_controller.dart' show exerciseKcalProvider;
import '../profile/profile_providers.dart' show profileProvider, waterGoalMlOf;
import 'home_controller.dart' show recordsProvider, summaryProvider;

@visibleForTesting
const adviceCardKey = Key('advice-card'); // index.html:106 .card.advice-home

@visibleForTesting
const adviceTitleKey = Key('advice-title'); // :107 .card-title

/// 第 i 条建议 li 行键（:108 ul#advice-list > li）
@visibleForTesting
Key adviceRowKey(int i) => Key('advice-row-$i');

class AdviceCard extends ConsumerWidget {
  const AdviceCard({super.key, required this.date});

  /// 当前页 date（首页语境=plateDateProvider，M7-T1 起可 ‹ › 翻动；≙ app.js:356 state.date）
  final String date;

  /// ≙ :357 `(state.body && state.body.weightKg) || 55`（?? 版，见文件头注）
  static num _weightOf(AsyncValue<Map<String, dynamic>> profile) {
    final p = profile.maybeWhen(data: (v) => v, orElse: () => null);
    final body = p?['body'];
    final w = body is Map ? body['weightKg'] : null;
    return w is num ? w : 55;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(summaryProvider(date));
    final s = summary.value;
    if (s == null) return const SizedBox.shrink(); // :351 if (!s) return

    // :352-359 makeAdviceCtx 六入参同源装配（s 此处已判非空，≙ :351 短路后的
    // state.summary）
    final profile = ref.watch(profileProvider);
    final ctx = makeAdviceCtx(
      summary: s,
      exerciseKcal: ref.watch(exerciseKcalProvider(date)),
      records: ref.watch(recordsProvider(date)).value ?? const [],
      isToday: date == todayIso(),
      weightKg: _weightOf(profile),
      // ≙ :358 `state.waterGoalMl`（app.js:1948 `goal.waterMl || 1600` 口径，
      // M6-T7 F4 收敛为 waterGoalMlOf 单一工具，round 对云整数值恒等）
      waterGoalMl: waterGoalMlOf(profile),
    );
    final tips = buildAdvice(ctx); // 最多 3 条（logic.js:212 slice(0,3)）

    return Container(
      key: adviceCardKey,
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
          // .card-title（index.html:107）：标题 + .more 副注
          Row(
            key: adviceTitleKey,
            children: [
              const Expanded(
                child: Text(
                  '每日建议',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '根据今日记录实时生成',
                style: const TextStyle(
                  fontSize: Tokens.textSm,
                  color: Tokens.ink3,
                ),
              ), // .more
            ],
          ),
          const SizedBox(height: Tokens.sp3),
          for (var i = 0; i < tips.length; i++) _row(i, tips[i]),
        ],
      ),
    );
  }

  /// li 行（:361）：`<span class=ai>emoji</span><span>文案</span>`
  Widget _row(int i, (String icon, String text) tip) {
    return Padding(
      key: adviceRowKey(i),
      padding: const EdgeInsets.symmetric(vertical: Tokens.sp1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tip.$1,
            style: const TextStyle(fontSize: Tokens.textLg),
          ), // .ai
          const SizedBox(width: Tokens.sp2),
          Expanded(
            child: Text(
              tip.$2,
              style: const TextStyle(
                fontSize: Tokens.textSm,
                color: Tokens.ink2,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
