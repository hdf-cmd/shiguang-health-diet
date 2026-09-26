// ShiguangFlutter/lib/features/home/home_screen.dart
// 首页（M2 Task 8：接真实数据；M3 Task 7：餐盘环 + 加载/空态区分）。
// 原 M1 静态版 home_static_screen.dart 演进而来。
// 数据源：home_controller.dart 的 summaryProvider/recordsProvider（date=todayProvider）。
// H5 行为对照 js/app.js:1926-1931（refresh 先拉 summary 再渲染）、js/app.js:595（记录拉取）；
// 目标值恒取云函数 summary.target（契约 dailySummary.target，M1 硬编码 1975 清除——M1 终审 I1）。
// M3-T7（终审 Minor M1 核销）：加载期显式静态骨架（plate-ring-skeleton /
// meal-skeleton，与报告页 T4 卡框骨架同路线——不排持续帧，pumpAndSettle 不死等），
// 仅"加载完成且无记录"才显零值态；餐盘环本体见 plate_ring.dart。
// M6-T3：①环额度接真实运动消耗（exerciseKcalProvider，app.js:298-309 两支
// note 逐字）；②三餐卡后插运动卡 HomeExerciseCard（app.js:1740-1754 +
// index.html:133-137）。卡序复核：H5 首页 plate(70)→advice(106)→water(111)→
// exercise(133)，运动卡为 home 末位卡；Flutter 首页现无建议/喝水卡（T4/T5
// 落地），运动卡按序置于三餐卡后=末位，advice/water 后续落地时应插在餐盘卡
// 与运动卡之间，与 H5 相对位一致。
// M6-T4：餐盘卡与三餐卡之间插 WaterCard——T3 卡序裁定落位：H5 相对序
// plate→(advice=T5 位)→water→exercise 保持；三餐卡系 M2 自有布局、H5 首页
// 无对应物（task-3-report §4），运动卡末位不动；建议卡 T5 落地时插在餐盘卡
// 与水卡之间。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/constants.dart' show exerciseLib;
import '../../domain/dates.dart' show dateLabelOf, todayIso;
import '../../domain/exercise.dart' show isRepRecord;
import '../../domain/js_compat.dart' show jsNumText;
import '../../domain/models.dart';
import '../exercise/exercise_controller.dart'
    show deleteExerciseRecord, exerciseKcalProvider, exercisesProvider;
import '../exercise/exercise_sheet.dart'
    show confirmDeleteExercise, openExerciseSheet;
import 'home_controller.dart';
import 'plate_ring.dart';
import 'water_card.dart' show WaterCard;

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
    // M6-T3 环接线（app.js:298 ex=state.exerciseKcal||0；在途/失败 orElse 0
    // ≙ H5 loadExercises 前缺省与 catch 降级，不阻断主流程）
    final ex = ref.watch(exerciseKcalProvider(date));
    final error = _errorMessage(summary, records);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Tokens.sp4),
        children: [
          const Text(
            '今日盘子',
            style: TextStyle(
              fontSize: Tokens.textXl,
              fontWeight: FontWeight.w800,
              color: Tokens.ink,
            ),
          ),
          const SizedBox(height: Tokens.sp4),
          if (error != null)
            _card(
              color: Tokens.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error,
                    style: const TextStyle(
                      color: Tokens.danger,
                      fontSize: Tokens.textMd,
                    ),
                  ),
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
            _plateCard(summary, ex),
            const SizedBox(height: Tokens.sp3),
            // 水卡（index.html:111-131；卡序复核见文件头 M6-T4 注）
            WaterCard(date: date),
            const SizedBox(height: Tokens.sp3),
            _mealsCard(records),
            const SizedBox(height: Tokens.sp3),
            // 运动卡（index.html:133-137，H5 首页末位卡；复核注释见文件头）
            HomeExerciseCard(date: date),
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
  /// [ex] 今日运动消耗（M6-T3 接线，app.js:298）；加载期不显 0 而显 —（同口径）。
  Widget _plateCard(AsyncValue<Summary> summary, int ex) {
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
            exerciseKcal: ex,
          );
    // budget = target + ex（app.js:299；M3 恒 0 口子已由实例参数闭环）
    final budget = s == null ? '—' : '${target + ex}';
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
                    _goalLine('运动消耗', s == null ? '—' : '$ex'),
                    // note（app.js:306-309 两支逐字；M6-T3 起 ex>0 支可真实到达，
                    // ex=0 支为 M3 已落文案）。加载期无 target 不显。
                    if (s != null) ...[
                      const SizedBox(
                        height: Tokens.sp2,
                      ), // .goal-note margin-top
                      Text(
                        key: const ValueKey('ring-note'),
                        ex > 0
                            ? '额度 ${target + ex} = 基准 $target + 运动 $ex kcal'
                            : '基准目标 $target kcal · 记运动后额度自动上调',
                        style: const TextStyle(
                          fontSize: Tokens.textXs,
                          color: Tokens.ink3,
                          height: 1.6,
                        ), // line-height 1.6
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
                  fontSize: Tokens.textXs,
                  color: Tokens.ink3,
                  height: 1.6,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// .goal-line（screens.css:164-165）：`标签 数字 kcal`，数字 b 语义
  /// （ink 色 w600 tabular-nums）
  Widget _goalLine(String label, String value) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            style: const TextStyle(
              color: Tokens.ink,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            text: value,
          ),
          const TextSpan(text: ' kcal'),
        ],
      ),
    );
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
              ('晚餐', 'dinner'),
            ])
              _mealRow(label, _recordsOf(list, meal)),
        ],
      ),
    );
  }

  static List<Map<String, dynamic>> _recordsOf(
    List<Map<String, dynamic>> list,
    String meal,
  ) => list.where((r) => r['meal'] == meal).toList(growable: false);

  Widget _mealRow(String label, List<Map<String, dynamic>> recs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.sp2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: const TextStyle(
                color: Tokens.ink2,
                fontSize: Tokens.textSm,
              ),
            ),
          ),
          Expanded(
            child: recs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: Tokens.sp1),
                    child: Text(
                      '未记录',
                      style: TextStyle(
                        color: Tokens.ink3,
                        fontSize: Tokens.textSm,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in recs)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Tokens.sp1,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${r['name'] ?? ''}（${r['portion'] ?? ''}）',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Tokens.ink,
                                    fontSize: Tokens.textSm,
                                  ),
                                ),
                              ),
                              const SizedBox(width: Tokens.sp2),
                              Text(
                                '${_n((r['kcal'] as num?) ?? 0)} kcal',
                                style: const TextStyle(
                                  color: Tokens.ink2,
                                  fontSize: Tokens.textSm,
                                  fontWeight: FontWeight.w700,
                                ),
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
            child: Text(
              '加载中',
              style: TextStyle(fontSize: Tokens.textXs, color: Tokens.ink3),
            ),
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
                  borderRadius: BorderRadius.all(
                    Radius.circular(Tokens.radiusSm),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------- M6-T3 首页运动卡（≙ app.js:1740-1754 + index.html:133-137） ---------- */

/// 行 ✕ 删除钮测试键（id 取自云记录）
@visibleForTesting
Key homeExDelKey(String id) => Key('home-ex-del-$id');

/// 今日运动卡：卡题两支（:1741 今日「今日运动」/非今日「运动 · {dateLabel}」）、
/// 副行「消耗 N kcal」（:1742）、行=emoji thumb+名+meta+「-kcal kcal」+✕
/// （:1743-1751）、空态「今天还没运动，点下方「记运动」」（:1754，error 降级同空
/// ≙ loadExercises catch→[]，不阻断主流程）、按钮「＋ 记运动」开 T2 弹层
/// （index.html:136 btn-add-exercise）。版式 R4 自主：对齐首页既有卡样式
/// （Tokens.surface 圆角阴影），行结构复用 _mealRow 观感。
/// 删除链走 T2 confirmDeleteExercise + deleteExerciseRecord，防重入守卫 ≙
/// app.js:1832「确认框已开则 return」（T2 评审移交①）。
class HomeExerciseCard extends ConsumerStatefulWidget {
  const HomeExerciseCard({super.key, required this.date});

  final String date;

  @override
  ConsumerState<HomeExerciseCard> createState() => _HomeExerciseCardState();
}

class _HomeExerciseCardState extends ConsumerState<HomeExerciseCard> {
  /// 确认框在开标志（≙ H5 全局 #confirm-sheet.show 判定，:1832）：
  /// 长按+click 双触同帧二次进入时直接 return。
  bool _confirmOpen = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _delete(Map<String, dynamic> rec) async {
    if (_confirmOpen) return; // :1832 逐义：确认框已开则 return
    _confirmOpen = true;
    late final bool ok;
    try {
      ok = await confirmDeleteExercise(context);
    } finally {
      _confirmOpen = false; // ≙ H5 确认框关闭即解除守卫（删除在途不再拦第二框）
    }
    if (!ok || !mounted) return; // :1834 取消零请求
    await deleteExerciseRecord(ref, widget.date, rec, _toast);
  }

  /// meta 行（app.js:1750）：rep 记录「{amount} {repUnit}」/ km「{amount} km」/
  /// 其余「{amount} 分钟」。云 GET 无 createdAt（T1 登记）→ isRepRecord 恒
  /// false → 次数型刷新后退化按分钟显示，H5 同病 bug-for-bug（测试钉死）。
  static String _metaOf(Map<String, dynamic> r) {
    final amount = jsNumText((r['amount'] as num?) ?? 0); // JS Number 串形（5.0→5）
    final key = '${r['key'] ?? ''}';
    final createdAt = (r['createdAt'] as num?)?.toInt() ?? 0;
    if (isRepRecord(key: key, createdAt: createdAt)) {
      // rep 判别命中 ⇒ key 必属 {pushup,rope}（_repKeys），exerciseLib 必含
      final lib = exerciseLib.firstWhere((l) => l.key == key);
      return '$amount ${lib.repUnit ?? '次'}';
    }
    return r['unit'] == 'km' ? '$amount km' : '$amount 分钟';
  }

  Widget _row(Map<String, dynamic> r) {
    final id = '${r['id']}';
    final name = '${r['name'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.sp1),
      child: Row(
        children: [
          Text(
            '${r['emoji'] ?? ''}',
            style: const TextStyle(fontSize: Tokens.textLg),
          ), // .thumb
          const SizedBox(width: Tokens.sp2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Tokens.ink,
                    fontSize: Tokens.textSm,
                  ),
                ), // .name
                Text(
                  _metaOf(r),
                  style: const TextStyle(
                    fontSize: Tokens.textXs,
                    color: Tokens.ink3,
                  ),
                ), // .meta
              ],
            ),
          ),
          const SizedBox(width: Tokens.sp2),
          Text(
            // 「-{kcal} kcal」 :1750
            '-${jsNumText((r['kcal'] as num?) ?? 0)} kcal',
            style: const TextStyle(
              color: Tokens.ink2,
              fontSize: Tokens.textSm,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: Tokens.sp1),
          Semantics(
            label: '删除$name', // aria-label 删除${r.name} :1751 逐字
            button: true,
            child: GestureDetector(
              key: homeExDelKey(id),
              onTap: () => _delete(r),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(Tokens.sp1),
                child: Text(
                  '✕',
                  style: TextStyle(fontSize: Tokens.textMd, color: Tokens.ink3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(exercisesProvider(widget.date));
    final total = ref.watch(exerciseKcalProvider(widget.date)); // :1742 reduce
    // 卡题两支（:1741）：dateLabelOf 不识别「今天」，调用方自判（dates.dart 注）
    final title = widget.date == todayIso()
        ? '今日运动'
        : '运动 · ${dateLabelOf(widget.date)}';
    final recs = list.value ?? const <Map<String, dynamic>>[];

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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '消耗 $total kcal', // .more（index.html:134）
                style: const TextStyle(
                  fontSize: Tokens.textSm,
                  color: Tokens.ink3,
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.sp3),
          if (list.value == null && list.isLoading)
            const _ExerciseSkeletonRow() // 首载骨架（与餐盘/三餐卡同口径）
          else if (recs.isEmpty)
            Text(
              '今天还没运动，点下方「记运动」', // :1754 逐字
              style: const TextStyle(
                fontSize: Tokens.textSm,
                color: Tokens.ink3,
              ),
            )
          else
            for (final r in recs) _row(r),
          const SizedBox(height: Tokens.sp3), // :137 btn margin-top --sp-3
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              // btn-soft btn-block ≙ soft 底通栏（R4 观感；Column stretch 安全位）
              style: FilledButton.styleFrom(
                backgroundColor: Tokens.primarySoft,
                foregroundColor: Tokens.primaryDeep,
              ),
              onPressed: () =>
                  openExerciseSheet(context, ref, date: widget.date),
              child: const Text('＋ 记运动'), // index.html:136 逐字
            ),
          ),
        ],
      ),
    );
  }
}

/// 运动记录首载骨架行：单条灰条占位（高 ≈ 行名+meta 两行，surfaceSoft）
class _ExerciseSkeletonRow extends StatelessWidget {
  const _ExerciseSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: Tokens.sp1),
      child: SizedBox(
        key: ValueKey('exercise-skeleton'),
        height: 34,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Tokens.surfaceSoft,
            borderRadius: BorderRadius.all(Radius.circular(Tokens.radiusSm)),
          ),
        ),
      ),
    );
  }
}
