// ShiguangFlutter/lib/features/home/water_card.dart
// 首页喝水卡（M6-T4 喝水闭环）。行为权威源 js/app.js:409-469 +
// index.html:111-131（water-widget DOM），文案逐字；版式 R4 自主（对齐首页
// 既有卡样式，色值取 H5 screens.css:303-392 water 族：fill 渐变
// #8FBCD4→nut-fat、杯描边 nut-fat、刻度 --surface）。
// 数字口径全部 summary.water 杯数 × waterCupMl(200)（:414）；
// 目标=waterGoalMlOf(profileProvider)（M6-T7 F3/F4 收敛：≙ app.js:1948
// `goal.waterMl || 1600` falsy 支——waterMl=0 也落 1600，顶格闸不误恒触发；
// 缺省/在途同 1600 档，≙ state.js:13 初值）。
// 乐观更新 ≙ app.js:438-449/457-467 同构：per-date 本地态
// waterOverrideProvider(date)（null=跟 provider；M7-T3 自 widget 单值字段
// _waterOverride 搬出，根治「切日期后旧日乐观值遮蔽新日 summary 真值」债；
// 函数体仅状态搬家，显示与 toast 文案零变更）→ 成功跟回包 water →
// 失败回滚 + toast「同步失败：{msg}」。
// 不移植登记（R4/M4 降级面，详见 task-4-report 差异表）：
// - buzz(6) 振动（app.js:440,68 navigator.vibrate）：Flutter 未引 haptics；
// - SGNative.updateWaterProgress 常驻通知/灵动岛同步（app.js:427-428）：
//   Android 原生壳专属，M4 已定降级面不移植；
// - animateNum 数字滚动（app.js:417 anime.js）与 fill/level 0.5s 过渡：
//   Flutter 直显终值（无隐式动画，避免 pumpAndSettle 语义纠缠）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/constants.dart' show waterCupMl;
import '../../domain/dates.dart' show dateLabelOf, todayIso;
import '../../domain/js_compat.dart' show jsOr;
import '../profile/profile_providers.dart' show profileProvider, waterGoalMlOf;
import 'goal_sheet.dart' show openGoalSheet;
import 'home_controller.dart'
    show healthApiProvider, summaryProvider, waterOverrideProvider, WaterOverride;

@visibleForTesting
const waterTitleKey = Key('water-title'); // index.html:113 #water-title

@visibleForTesting
const waterMlKey = Key('water-ml'); // :114 #water-ml 大数字

@visibleForTesting
const waterGoalEditKey = Key('water-goal-edit'); // :115 目标行按钮

@visibleForTesting
const waterBarKey = Key('water-bar'); // :122 .water-bar 容器

@visibleForTesting
const waterFillKey = Key('water-fill'); // :123 #water-fill 填充条

@visibleForTesting
const waterCupKey = Key('water-cup'); // :117 杯按钮（喝一杯点击区）

@visibleForTesting
const waterUndoKey = Key('water-undo'); // :129 撤销（Visibility 载体）

/// H5 water-widget 语义色（screens.css:314-355：渐变起色 #8FBCD4 为 css 字面量）
const _waterLight = Color(0xFF8FBCD4);
const _waterFillGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [_waterLight, Tokens.nutFat],
);
const _cupFillGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [_waterLight, Tokens.nutFat],
);

class WaterCard extends ConsumerStatefulWidget {
  const WaterCard({super.key, required this.date});

  /// 当前页 date（首页语境=plateDateProvider，M7-T1 起可 ‹ › 翻动；喝一杯/撤销请求均带此 date，
  /// ≙ app.js:443/460 HealthAPI.addWater(±1, state.date)）
  final String date;

  @override
  ConsumerState<WaterCard> createState() => _WaterCardState();
}

class _WaterCardState extends ConsumerState<WaterCard> {
  /// per-date 乐观态写入口（≙ 旧 setState(_waterOverride = …)；M7-T3 起
  /// 状态搬进 waterOverrideProvider(widget.date)，重渲染由 build 的 watch
  /// 自动触发，不再走 setState）。
  WaterOverride _override() =>
      ref.read(waterOverrideProvider(widget.date).notifier);

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// ≙ app.js:449/467 `e.message || '网络异常'`（ApiException 露后端 message）
  static String _errText(Object e) =>
      e is ApiException ? jsOr(e.message, '网络异常') : '网络异常';
      // ≙ e.message || '网络异常'（终审 Minor-1 与 exercise 族统一口径）

  /// 喝一杯（≙ drinkOneCup，app.js:432-451）
  Future<void> _drink(int n, int goal) async {
    if (n * waterCupMl >= goal) {
      _toast('目标 ${goal}ml 已达成，明天继续'); // :434 逐字
      return; // :435 零请求（H5 直接 return）
    }
    final prev = n;
    _override().bump(prev, 1); // :438 乐观
    // :439 renderWater → :441 toast（乐观值口径，先于回包）
    _toast('+${waterCupMl}ml · 已喝 ${(prev + 1) * waterCupMl}ml');
    try {
      final res = await ref
          .read(healthApiProvider)
          .addWater(1, widget.date); // :443
      final water = (res['water'] as num?)?.round(); // 云回包恒含 water（:444 截断回显）
      if (!mounted) return;
      _override().apply(water ?? prev + 1); // :444 跟回包
    } catch (e) {
      if (!mounted) return;
      _override().apply(prev); // :447 回滚
      _toast('同步失败：${_errText(e)}'); // :449
    }
  }

  /// 撤销上一杯（≙ #water-undo click，app.js:454-469）
  Future<void> _undo(int n) async {
    if (n <= 0) return; // :455（按钮隐藏态本不可点，双保险同 H5）
    final prev = n;
    _override().bump(prev, -1); // :457 乐观
    _toast('已退回一杯 · 剩 ${(prev - 1) * waterCupMl}ml'); // :459 乐观值口径
    try {
      final res = await ref
          .read(healthApiProvider)
          .addWater(-1, widget.date); // :461
      final water = (res['water'] as num?)?.round();
      if (!mounted) return;
      _override().apply(water ?? prev - 1); // :462 跟回包
    } catch (e) {
      if (!mounted) return;
      _override().apply(prev); // :465 回滚
      _toast('同步失败：${_errText(e)}'); // :467
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(summaryProvider(widget.date));
    final goal = waterGoalMlOf(ref.watch(profileProvider));
    final loading = !summary.hasValue;
    final n = ref.watch(waterOverrideProvider(widget.date)) ??
        summary.value?.water.round() ?? 0;
    final ml = n * waterCupMl; // :414
    final reached = ml >= goal; // :415
    final pct = (ml / goal * 100).clamp(0.0, 100.0); // :416 Math.min(100,·)

    // 卡题两支（:413）：dateLabelOf 不识别「今天」，调用方自判（dates.dart 注）
    final title = widget.date == todayIso()
        ? '喝水打卡'
        : '喝水 · ${dateLabelOf(widget.date)}';

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
          // .water-head（index.html:112-121）：左标题/大数字/目标行，右杯按钮
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: waterTitleKey,
                      style: const TextStyle(
                        fontSize: Tokens.textMd,
                        fontWeight: FontWeight.w600,
                        color: Tokens.ink,
                      ),
                    ), // .water-title
                    const SizedBox(height: 2), // .water-num margin-top:2px
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          // #water-ml 大数字（text-xl w600 tabular-nums；
                          // animateNum 滚动不移植，直显终值）
                          loading ? '—' : '$ml',
                          key: waterMlKey,
                          style: const TextStyle(
                            fontSize: Tokens.textXl,
                            fontWeight: FontWeight.w600,
                            color: Tokens.ink,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const Text(
                          ' ml',
                          style: TextStyle(
                            fontSize: Tokens.textSm,
                            color: Tokens.ink3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2), // .water-goal-edit margin-top
                    Semantics(
                      link: true,
                      child: GestureDetector(
                        key: waterGoalEditKey, // #water-goal-edit → openGoalSheet
                        onTap: () => openGoalSheet(context, ref, goalMl: goal),
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              fontSize: Tokens.textXs,
                              color: Tokens.primary,
                            ),
                            children: [
                              const TextSpan(text: '目标 '),
                              TextSpan(
                                text: '$goal',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(text: ' ml'),
                              const WidgetSpan(
                                child: SizedBox(width: Tokens.sp2),
                              ),
                              const TextSpan(
                                text: '点击修改', // .wge-hint
                                style: TextStyle(color: Tokens.ink3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Tokens.sp4), // .water-head gap --sp-4
              _cup(pct / 100),
            ],
          ),
          // .water-bar（index.html:122-126）：fill 宽 pct%、刻度每杯一段 2px 缝
          SizedBox(
            height: 14, // screens.css:311 height:14px
            child: GestureDetector(
              key: waterBarKey,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999), // radius-full
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: Tokens.surfaceSoft),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: pct / 100,
                        heightFactor: 1,
                        child: DecoratedBox(
                          key: waterFillKey,
                          decoration: const BoxDecoration(
                            gradient: _waterFillGradient,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TicksPainter(
                          cups: (goal / waterCupMl).round(),
                        ),
                      ), // #water-ticks
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Tokens.sp2), // .water-foot margin-top --sp-2
          // .water-foot（index.html:127-130）：hint + 撤销
          Row(
            children: [
              Expanded(
                child: Text(
                  loading
                      ? '加载中'
                      : (reached
                            ? '目标已达成 🎉' // :424 reached 支逐字
                            : '已喝 $n 杯 · 每杯 ${waterCupMl}ml'), // :424 未达支逐字
                  style: const TextStyle(
                    fontSize: Tokens.textSm,
                    color: Tokens.ink3,
                  ),
                ),
              ),
              Visibility(
                key: waterUndoKey,
                visible:
                    !loading &&
                    n > 0, // :425 visibility:hidden 保位 ≙ maintainSize
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: GestureDetector(
                  onTap: () => _undo(n),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: Tokens.sp1,
                      vertical: Tokens.sp1,
                    ),
                    child: Text(
                      '撤销上一杯', // index.html:129 逐字
                      style: TextStyle(
                        fontSize: Tokens.textXs,
                        color: Tokens.ink3,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                        decorationColor: Tokens.ink3,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 杯按钮（≙ .water-cup，index.html:117-120/screens.css:345-360）：
  /// 58×74、nut-fat 描边、底部水位=当日进度、中央「200ml」字。点击喝一杯。
  Widget _cup(double level) {
    return Semantics(
      button: true,
      label: '喝一杯 ${waterCupMl}ml', // aria-label 逐字（index.html:117）
      child: GestureDetector(
        key: waterCupKey,
        onTap: () {
          final summary = ref.read(summaryProvider(widget.date));
          final n = ref.read(waterOverrideProvider(widget.date)) ??
              summary.value?.water.round() ?? 0;
          _drink(n, waterGoalMlOf(ref.read(profileProvider)));
        },
        child: SizedBox(
          width: 58,
          height: 74,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(10),
              bottom: Radius.circular(18),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Tokens.surface,
                border: Border.all(color: Tokens.nutFat, width: 2),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                  bottom: Radius.circular(18),
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: level.clamp(0.0, 1.0),
                        widthFactor: 1,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: _cupFillGradient,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: Center(
                      child: Text(
                        '${waterCupMl}ml', // 杯身「200ml」字（index.html:119）
                        style: TextStyle(
                          fontSize: Tokens.textXs,
                          fontWeight: FontWeight.w600,
                          color: Tokens.ink2,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 刻度线（≙ #water-ticks repeating-linear-gradient：每杯一段、段界 2px 缝
/// screens.css:320-325）——surface 色竖线盖在 fill 上。
class _TicksPainter extends CustomPainter {
  _TicksPainter({required this.cups});

  /// 段数 = goal/200（云截断后恒 [4,15]）
  final int cups;

  @override
  void paint(Canvas canvas, Size size) {
    if (cups <= 1) return;
    final paint = Paint()..color = Tokens.surface;
    for (var i = 1; i < cups; i++) {
      final x = size.width * i / cups;
      canvas.drawRect(
        Rect.fromLTWH(x - 1, 0, 2, size.height),
        paint,
      ); // calc(seg% - 2px) 宽 2
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) => old.cups != cups;
}
