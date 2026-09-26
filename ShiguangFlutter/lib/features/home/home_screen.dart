// ShiguangFlutter/lib/features/home/home_screen.dart
// 首页（M2 Task 8：接真实数据；M3 Task 7：餐盘环 + 加载/空态区分）。
// 原 M1 静态版 home_static_screen.dart 演进而来。
// 数据源：home_controller.dart 的 summaryProvider/recordsProvider
// （date=plateDateProvider，M7-T1 起可被 plate-head ‹ › 翻动）。
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
// M6-T5：建议卡 AdviceCard 落位（index.html:106-109 .card.advice-home）——
// 卡位复核：H5 实序 plate(70)→advice(106)→water(111)→exercise(133)，
// advice 在餐盘卡内环/营养条整体之后、水卡之前，即 T4 预留位，按序插入。
// M7-T1：①日期状态机 plateDateProvider（≙ H5 state.date）——五卡日期源由
// todayProvider 改 watch plateDateProvider，餐盘卡顶插 plate-head
// `‹ [日期胶囊] ›`（index.html:71-75，文案 ≙ app.js:209-211 三态逐字，
// › 在今天 visibility 保位隐藏 ≙ :213，未来闸 toast「已经到今天了」≙ :219）；
// ②页头加问候头（≙ index.html:61-67 .home-head + app.js:287-294
// renderGreeting 五档/昵称/日期行逐字，恒用 DateTime.now()，不 watch
// plateDateProvider）。页标题「今日盘子」系 M1 静态版遗留、shell/auth 等
// 4 处既有用例的渲染哨兵，本任务不动（与 H5 首页无页标题的差异登记 T1 报告）。
// 取数链：切日期后不手动 invalidate 一梭子——summary/records 与运动两族
// （exercisesProvider/exerciseKcalProvider，M7-T2 起皆 autoDispose）随 watch
// 自然起新流，同日回访亦重取（≙ app.js:221-223 每次切日期并行拉取）。
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
import '../profile/profile_providers.dart' show profileProvider;
import 'advice_card.dart' show AdviceCard;
import 'home_controller.dart';
import 'plate_ring.dart';
import 'water_card.dart' show WaterCard;

/* ---------- M7-T1 plate-head（≙ index.html:71-75 + app.js:201-224） ---------- */

/// 日期胶囊（index.html:73 #plate-date）
@visibleForTesting
const plateDateKey = Key('plate-date');

/// ‹ 前一天（index.html:72 #plate-prev，恒在）
@visibleForTesting
const platePrevKey = Key('plate-prev');

/// › 后一天（index.html:74 #plate-next，date==今天 时保位隐藏）
@visibleForTesting
const plateNextKey = Key('plate-next');

/// .plate-nav 圆钮尺寸（screens.css:143 width/height:30px）
const _plateNavSize = 30.0;

/* ---------- M7-T1 问候头（≙ index.html:61-67 + app.js:287-294） ---------- */

/// 问候语行（index.html:63 #home-greeting）
@visibleForTesting
const greetingKey = Key('home-greeting');

/// 问候头日期行（index.html:64 #home-date）
@visibleForTesting
const greetingDateKey = Key('home-date');

/// 问候语五档（app.js:288-290 逐字）：h<6 夜深了 / <11 早上好 / <14 中午好 /
/// <18 下午好 / else 晚上好；有昵称拼「{greet}，{nickname}」（:290 全角逗号），
/// 空昵称 ≙ H5 falsy → 裸问候语。
@visibleForTesting
String greetingTextOf(int hour, String? nickname) {
  final greet = hour < 6
      ? '夜深了'
      : hour < 11
      ? '早上好'
      : hour < 14
      ? '中午好'
      : hour < 18
      ? '下午好'
      : '晚上好';
  return (nickname == null || nickname.isEmpty) ? greet : '$greet，$nickname';
}

/// 问候头日期行（app.js:291-293 逐字）：`M月D日 · 星期X`
/// weeks 表下标 ≙ JS getDay()（日=0…六=6），Dart weekday%7 同序。
@visibleForTesting
String greetingDateLineOf(DateTime d) {
  const weeks = ['日', '一', '二', '三', '四', '五', '六'];
  return '${d.month}月${d.day}日 · 星期${weeks[d.weekday % 7]}';
}

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
    // M7-T1：日期源切 plateDateProvider（≙ H5 state.date，可被 ‹ › 翻动）；
    // todayProvider 仍供记录页/身体卡等非首页语境使用。
    final date = ref.watch(plateDateProvider);
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
          // 问候头（index.html:61-67 .home-head .hello；app.js:287-294）。
          // 恒用 DateTime.now()，不吃 plateDateProvider（‹ › 翻日期不改问候）。
          _greetingHead(ref),
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
                  // plate-head 在 error 态照常在场（≙ index.html:71-75 系静态
                  // markup、renderPlateDate :201 不读 summary）：取数失败仍可用
                  // ‹ › 翻日期重试历史日，不被整张卡一起吞掉。
                  const _PlateHead(),
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
            // 建议卡（index.html:106-109；卡序复核见文件头 M6-T5 注。
            // summary 在途整卡不渲染 ≙ app.js:351——卡体 shrink 消失，但其
            // 后 SizedBox(sp3) 间距照常叠置：加载期餐盘卡与水卡之间为
            // 2×sp3 空档（M6-T7 F6 勘误：原「不叠空卡」表述不实））
            AdviceCard(date: date),
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

  /// 问候头（≙ index.html:61-67 .home-head .hello：h2#home-greeting +
  /// p#home-date；app.js:287-294 renderGreeting 逐字）。
  /// 昵称源 profileProvider（≙ :1947 renderGreeting(profile.nickname)；
  /// 在途/失败无数据 → 裸问候语 ≙ :1914 首次 renderGreeting() 无参调用）。
  /// 时钟恒 DateTime.now()：不 watch plateDateProvider（‹ › 翻日期不改问候，
  /// 亦不加定时器——H5 仅 loadMainBundle 调一次，档位刷新时机差异登记 R4）。
  Widget _greetingHead(WidgetRef ref) {
    final now = DateTime.now();
    final p = ref.watch(
      profileProvider,
    ).maybeWhen(data: (v) => v, orElse: () => null);
    final nick = p?['nickname'];
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4), // .home-head padding 12px 0 4px
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            key: greetingKey,
            greetingTextOf(now.hour, nick is String ? nick : null),
            style: const TextStyle(
              fontSize: Tokens.textXl,
              fontWeight: FontWeight.w700,
              color: Tokens.ink,
              letterSpacing: -0.01, // .hello h2 letter-spacing -.01em
            ),
          ),
          const SizedBox(height: 4), // .hello p margin-top 4px
          Text(
            key: greetingDateKey,
            greetingDateLineOf(now),
            style: const TextStyle(
              fontSize: Tokens.textXs,
              color: Tokens.ink3,
            ),
          ),
        ],
      ),
    );
  }

  /// 餐盘卡（index.html:70-104 .card.plate-card，surface 白底——M2 深色占位卡
  /// 替换之）。结构 = plate-head（index.html:71-75，M7-T1 落地）+ .plate-top
  /// （左环右 aside，screens.css:150）+ nutrient-note（index.html:103）。
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
          const _PlateHead(),
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

/* ---------- M7-T1 plate-head（≙ index.html:71-75 + app.js:201-224） ---------- */

/// 餐盘卡日期导航行：`‹ [日期胶囊] ›`（.plate-head：居中、gap --sp-3、
/// margin-bottom --sp-2，screens.css:141）。
/// 胶囊三态文案 ≙ app.js:209-211（home_controller.plateDatePartsOf）；
/// › 在 date==今天 时保位隐藏 ≙ :213 style.visibility='hidden'（占格不消失、
/// 不可点，Visibility maintain* 组合即 CSS visibility 语义）；‹ 恒在（:225）。
/// 未来闸 toast「已经到今天了」≙ :219（shiftPlateDate 内）。
/// 不移植面（本任务裁定）：卡内左右滑动通道（app.js:227-259）——「右滑看历史」
/// 仅系胶囊小字文案，‹ › 按钮即完整可达路径。
class _PlateHead extends ConsumerWidget {
  const _PlateHead();

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(plateDateProvider);
    final (main, small) = plateDatePartsOf(date);
    final isToday = date == todayIso();

    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.sp2), // .plate-head margin-bottom
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center, // .plate-head justify-content
        children: [
          _plateNavButton(
            key: platePrevKey,
            glyph: '‹',
            aria: '前一天', // index.html:72 aria-label 逐字
            onTap: () => shiftPlateDate(ref, -1, (m) => _toast(context, m)),
          ),
          const SizedBox(width: Tokens.sp3), // gap --sp-3
          // 胶囊：主文案 + small 副文案（.plate-date / .plate-date small）
          Semantics(
            label: plateDateLabelOf(date), // ≙ #plate-date.textContent 单串
            excludeSemantics: true,
            child: Container(
              key: plateDateKey,
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.sp2,
                vertical: Tokens.sp1,
              ),
              decoration: BoxDecoration(
                color: Tokens.surfaceSoft,
                borderRadius: BorderRadius.circular(Tokens.radiusSheet),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    main,
                    style: const TextStyle(
                      fontSize: Tokens.textSm,
                      fontWeight: FontWeight.w600,
                      color: Tokens.ink,
                    ),
                  ),
                  const SizedBox(width: 4), // .plate-date small margin-left:4px
                  Text(
                    small,
                    style: const TextStyle(
                      fontSize: Tokens.textXs,
                      fontWeight: FontWeight.w400,
                      color: Tokens.ink3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Tokens.sp3),
          Visibility(
            // CSS visibility:hidden 等价组合：保 state/size（占格不塌）、
            // 默认 maintainInteractivity=false → 隐藏态不可点、不入语义树。
            visible: !isToday,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: true,
            child: _plateNavButton(
              key: plateNextKey,
              glyph: '›',
              aria: '后一天', // index.html:74 aria-label 逐字
              onTap: () => shiftPlateDate(ref, 1, (m) => _toast(context, m)),
            ),
          ),
        ],
      ),
    );
  }
}

/// .plate-nav 圆钮（screens.css:142-147：30×30 圆、--surface-soft 底、
/// --ink-2 字、font-size:18px、line-height:1）。
Widget _plateNavButton({
  required Key key,
  required String glyph,
  required String aria,
  required VoidCallback onTap,
}) {
  return Semantics(
    key: key,
    label: aria,
    button: true,
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: _plateNavSize,
        height: _plateNavSize,
        decoration: const BoxDecoration(
          color: Tokens.surfaceSoft,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            glyph,
            style: const TextStyle(
              fontSize: 18,
              height: 1,
              color: Tokens.ink2,
            ),
          ),
        ),
      ),
    ),
  );
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
/// 删除链走 T2 confirmDeleteExercise + deleteExerciseRecord（M7-T2 起为
/// notifier.remove 乐观链：确认 → 行即摘+「已删除运动记录」即弹 → await →
/// 失败回插），防重入守卫 ≙ app.js:1832「确认框已开则 return」（T2 评审移交①）。
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

  /// meta 行（app.js:1746 isRepRecord 两支）：rep 记录「{amount} {repUnit}」/
  /// km「{amount} km」/其余「{amount} 分钟」。M7-T2 时序：temp 行自带
  /// createdAt（:1813）→ 保存即显「N 次」；云 GET 不回 createdAt（T1 登记）→
  /// 重取后回退分钟档——「即显次数、刷新退化」H5 同款，home_exercise_test 钉④
  /// 锁死。本渲染器对 temp/云行同形（:1740-1754 无任何 temp 特殊文案）。
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
