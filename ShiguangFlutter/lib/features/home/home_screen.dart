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
// M8-②：三餐记录卡整卡删除（老大 09-27 真机反馈）——首页不再 watch
// recordsProvider，取数/error 闸/重试随之收敛为 summary 单路；餐次数据只在
// 记录页呈现。M8-③：盘子卡卡内横滑切日（M7-T1 裁定的「不移植面」翻案——
// 胶囊小字「右滑看历史」自本批起言行一致）：右滑=前一天、左滑=后一天，
// 阈值 ±60px，走 shiftPlateDate（未来闸/三态文案自动生效）。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../data/mi_cloud_client.dart' show MiDailyActivity;
import '../../data/mi_daily_activity_store.dart' show miDailyActivityProvider;
import '../../data/swr_cache.dart' show swrCacheProvider;
import '../../domain/constants.dart' show exerciseLib;
import '../../domain/dates.dart' show dateLabelOf, todayIso;
import '../../domain/exercise.dart' show isRepRecord;
import '../../domain/js_compat.dart' show jsNumText;
import '../../domain/metabolism.dart' show computeMetabolism;
import '../../domain/models.dart' show Body;
import '../common/stagger.dart' show Stagger;
import '../exercise/exercise_controller.dart'
    show deleteExerciseRecord, exerciseKcalProvider, exercisesProvider;
import '../exercise/exercise_sheet.dart'
    show confirmDeleteExercise, openExerciseSheet;
import '../profile/profile_providers.dart' show profileProvider;
import 'advice_card.dart' show AdviceCard;
import 'home_controller.dart';
import 'plate_ring.dart';
import 'steps_card.dart' show StepsCard;
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

  /// error 态文案：ApiException 露后端 message（H5 err.textContent = e.message 语义），
  /// 其余异常给通用兜底。M8-②：records 单路随三餐卡退役，闸只挂 summary。
  static String? _errorMessage(AsyncValue<Object?> a) {
    final err = a.hasError ? a.error : null;
    if (err == null) return null;
    return err is ApiException ? err.message : '加载失败，请检查网络后重试';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // M7-T1：日期源切 plateDateProvider（≙ H5 state.date，可被 ‹ › 翻动）；
    // todayProvider 仍供记录页/身体卡等非首页语境使用。
    final date = ref.watch(plateDateProvider);
    final summary = ref.watch(summaryProvider(date));
    final error = _errorMessage(summary);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Tokens.sp4),
        children: [
          // M9-T6（B2 接线）：问候头+页标题合并为错峰入场首项（index 0），
          // 其后卡序 盘子=1 / 建议=2 / 水=3 / 运动=4；error 卡占盘子位同
          // index 1。盘子卡不包 PressableScale（T5 移交裁定：与
          // _PlateSwipeZone 手势竞争）。
          // 问候头（index.html:61-67 .home-head .hello；app.js:287-294）。
          // 恒用 DateTime.now()，不吃 plateDateProvider（‹ › 翻日期不改问候）。
          Stagger(
            index: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _greetingHead(ref),
                const Text(
                  '今日盘子',
                  style: TextStyle(
                    fontSize: Tokens.textXl,
                    fontWeight: FontWeight.w800,
                    color: Tokens.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.sp4),
          if (error != null)
            Stagger(
              index: 1,
              child: _homeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // plate-head 在 error 态照常在场（≙ index.html:71-75 系静态
                  // markup、renderPlateDate :201-224 实读不读 summary）：取数失败
                  // 仍可用 ‹ › 翻日期重试历史日，不被整张卡一起吞掉。
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
                        // 重试 = invalidate summary 重新取数（非本地翻牌）。
                        // M9-T2：先删 SWR 键再 invalidate——重试必须绕开旧
                        // 缓存强制走网络（error 卡只在首访失败出现，删键
                        // 亦防「首访成功后又失败」边角面的播种残留）。
                        ref.read(swrCacheProvider).invalidate('summary.$date');
                        ref.invalidate(summaryProvider(date));
                      },
                      child: const Text('重试'),
                    ),
                  ),
                ],
              ),
            ),
            )
          else ...[
            Stagger(
              index: 1,
              child: const _PlateSwipeZone(child: _PlateCard()),
            ),
            // 建议卡（index.html:106-109；卡序复核见文件头 M6-T5 注。
            // summary 在途整卡不渲染 ≙ app.js:351 `if (!s || !el) return`——
            // 卡体连同其顶部 sp3 间距一并消失（间距在 AdviceCard 卡体条件
            // 构造内，M7-T8 Minor-3：加载期餐盘卡与水卡之间恒为单份 sp3，
            // 不再叠 2×sp3 空档——原双空档系 M6-T7 F6 勘误登记的既知面））
            Stagger(index: 2, child: AdviceCard(date: date)),
            const SizedBox(height: Tokens.sp3),
            // 水卡（index.html:111-131；卡序复核见文件头 M6-T4 注）
            Stagger(index: 3, child: WaterCard(date: date)),
            const SizedBox(height: Tokens.sp3),
            // M8-②：三餐记录卡整卡删除——餐次呈现收敛到记录页，
            // 首页卡序变 盘子→建议→水→运动。
            // 运动卡（index.html:133-137，H5 首页末位卡；复核注释见文件头）
            Stagger(index: 4, child: HomeExerciseCard(date: date)),
            const SizedBox(height: Tokens.sp3),
            // 步数卡（M17 增件）：小米云每日活动缓存，随所选日期联动。
            Stagger(index: 5, child: StepsCard(date: date)),
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

}

/* ---------- M8-③ 盘子卡 + 卡内横滑切日 ---------- */

/// 首页卡片壳（surface 圆角阴影，M8-② 随三餐卡删除从实例方法升为顶层
/// 共用——HomeScreen error 卡与 _PlateCard 同源）。
Widget _homeCard({required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(Tokens.sp5),
    decoration: BoxDecoration(
      color: Tokens.surface,
      borderRadius: BorderRadius.circular(Tokens.radiusLg),
      boxShadow: Tokens.shadowCard,
    ),
    child: child,
  );
}

/// 餐盘卡（index.html:70-104 .card.plate-card，surface 白底——M2 深色占位卡
/// 替换之）。结构 = plate-head（index.html:71-75，M7-T1 落地）+ .plate-top
/// （左环右 aside，screens.css:150）+ nutrient-note（index.html:103）。
/// 加载期（summary 未回）：环位显静态骨架、aside 数字显"—"——与"加载完成
/// 且无记录"的零值态（真实 0/预算数字）可分辨（M2 终审 Minor M1）。
/// M8-③：自 HomeScreen 实例方法拆为独立 ConsumerWidget——日期源
/// plateDateProvider 自 watch，供 _PlateSwipeZone 包裹（横滑切日手势层）。
class _PlateCard extends ConsumerWidget {
  const _PlateCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(plateDateProvider);
    final summary = ref.watch(summaryProvider(date));
    final ex = ref.watch(exerciseKcalProvider(date));
    final s = summary.value;
    // H5 renderRing 入参先 Math.round 语义取整（本仓整数呈现口径同源）
    final kcal = s?.kcal.round() ?? 0;
    final cloudTarget = s?.target.round() ?? 0;
    // 手表口径：当天有手表活动热量 → TDEE = BMR + 手表活动，额度不再叠加
    // 运动（全天活动已含运动）；无手表数据回落云端系数口径（旧行为）。
    final watchMap = ref.watch(miDailyActivityProvider).maybeWhen(
          data: (m) => m,
          orElse: () => const <String, MiDailyActivity>{},
        );
    // 有手表数据那天：TDEE = BMR + max(手表活动, 运动记录)；
    // 无手表数据的日期保持旧公式（云端 target + 运动），手动记录照常生效。
    final watchKcal = watchMap[date]?.activeKcal ?? 0;
    final profile = ref.watch(profileProvider).maybeWhen(
          data: (v) => v,
          orElse: () => null,
        );
    var watchTdee = 0;
    var watchOn = false;
    num watchActive = 0;
    var effectiveTarget = cloudTarget;
    num configuredDeficit = 0;
    final active = math.max(watchKcal, ex);
    if (watchKcal > 0 && profile != null) {
      final bodyMap = profile['body'];
      if (bodyMap is Map) {
        final body = Body.fromMap(bodyMap.cast<String, Object?>());
        final goal = profile['goal'];
        final tw =
            goal is Map ? (goal['targetWeight'] as num?)?.toDouble() : null;
        final m = computeMetabolism(body, tw, null, null, active);
        watchTdee = m.tdee;
        watchActive = active;
        effectiveTarget = m.suggest.round();
        configuredDeficit = body.deficit;
        watchOn = true;
      }
    }
    final extra = watchOn ? 0 : ex;
    final ring = s == null
        ? _PlateRingSkeleton()
        : PlateRing(
            kcal: kcal,
            target: effectiveTarget,
            carb: s.carb.round(),
            protein: s.protein.round(),
            fat: s.fat.round(),
            exerciseKcal: extra,
          );
    final budgetInt = effectiveTarget + extra;
    final budget = s == null ? '—' : '$budgetInt';
    return _homeCard(
      child: Column(
        key: const ValueKey('plate-card'),
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
                    // note：手表支按「手表消耗 − 缺口」；无手表数据沿用旧文案。
                    if (s != null) ...[
                      const SizedBox(
                        height: Tokens.sp2,
                      ), // .goal-note margin-top
                      Text(
                        key: const ValueKey('ring-note'),
                        watchOn
                            ? '额度 $budgetInt = 消耗 $watchTdee（BMR+活动 $watchActive）'
                                ' − 缺口 ${watchTdee - effectiveTarget} kcal'
                                '${configuredDeficit > watchTdee - effectiveTarget ? '（预设 $configuredDeficit，受 BMR 下限限制）' : ''}'
                                '${watchKcal >= ex ? ' · 手表活动口径' : ' · 按运动记录口径'}'
                            : (ex > 0
                                ? '额度 ${effectiveTarget + ex} = 基准 $effectiveTarget + 运动 $ex kcal'
                                : '基准目标 $effectiveTarget kcal · 记运动后额度自动上调'),
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
                watchOn
                    ? '营养素目标 = 基准 $effectiveTarget × 供能比 50%/25%/25% ÷ '
                        '(4/4/9) kcal；热量额度按手表全天消耗，不含额外运动'
                    : '营养素目标 = 基准 $effectiveTarget × 供能比 50%/25%/25% ÷ '
                        '(4/4/9) kcal，不含运动额度；热量额度含运动，两者基数不同',
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

/// 盘子卡横滑切日手势层（M8-③， H5 app.js:227-259 卡内左右滑动通道）。
/// 语义：**右滑（dx>0）=看历史=前一天；左滑=后一天**，阈值 ±60px（H5
/// 阈值口径），走 shiftPlateDate——未来闸 toast「已经到今天了」/三态文案
/// 自动生效。与壳层 PageView 的横滑切 tab 竞争：卡内 GestureDetector 位于
/// 更深层，手势竞技场按最深优先接纳——卡内起滑切日期、卡外起滑切 tab
/// （plate_swipe_test 双向钉死）。
class _PlateSwipeZone extends ConsumerStatefulWidget {
  const _PlateSwipeZone({required this.child});

  final Widget child;

  @override
  ConsumerState<_PlateSwipeZone> createState() => _PlateSwipeZoneState();
}

class _PlateSwipeZoneState extends ConsumerState<_PlateSwipeZone> {
  /// 本次拖拽的水平累计位移（drag start 归零，end 判定后归零）
  double _dx = 0;

  static const _threshold = 60.0;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _end() {
    final dx = _dx;
    _dx = 0;
    if (dx > _threshold) {
      shiftPlateDate(ref, -1, _toast); // 右滑 → 前一天（看历史）
    } else if (dx < -_threshold) {
      shiftPlateDate(ref, 1, _toast); // 左滑 → 后一天（今天被未来闸拦）
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('plate-swipe'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => _dx += d.delta.dx,
      onHorizontalDragEnd: (_) => _end(),
      child: widget.child,
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
/// M8-③：卡内左右滑动通道（app.js:227-259）翻案落地——见 _PlateSwipeZone，
/// 「右滑看历史」胶囊小字自本批起言行一致。
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
      // （首屏实读 H5 app.js:1748 无兜底：`EXERCISE_LIB.find(...).repUnit`）。
      // 书面销账（终审 Minor-4，M7-T8）：`?? '次'` 兜底位 H5 该位为
      // find 未命中即 TypeError（生产不可达——lib 恒含两键且 pushup/rope
      // 均带 repUnit，constants.dart:90/93），本端保留防御，不逐字搬 throw。
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
