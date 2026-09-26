// ShiguangFlutter/lib/features/home/goal_sheet.dart
// 喝水目标弹层（M6-T4 喝水闭环，与 T5 合并裁定后的归属：本任务全量落地）。
// 行为权威源 js/app.js:470-493 + index.html:295-308（goal-sheet DOM）+
// css/screens.css:361-382（.goal-stepper）。文案逐字：
// - 开层预填当前目标（:473 $('#water-goal-val').value = state.waterGoalMl）；
// - bumpGoal ±200 截断 [800,3000]，顶格值不动 + toast「最大 3000ml」/
//   「最小 800ml」（:476-482 逐支）；
// - 失焦/变更归一 ≙ bindStepperNorm('#water-goal-val',800,3000,null,after)
//   （app.js:1653-1654）：NaN→min、clamp、四舍五入对齐 200ml 整数倍——
//   云端只做 [800,3000] 截断、无 200 归一（上游事实），归一是本 UI 层职责；
// - 保存 setWaterGoal → 关层 → toast「喝水目标已设为 {回包 waterGoalMl}ml」
//   （:486-492 时序：await 成功才关层）；成功后 invalidate(profileProvider)
//   → 水卡 goal 行与「我的」页联动（上游事实）。
// 差异登记（见 task-4-report）：保存失败 H5 未 catch → 静默且层开；Flutter
// toast「同步失败：{msg}」且不关层（通知面补强，时序一致）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/constants.dart'
    show waterCupMl, waterGoalMin, waterGoalMax;
import '../../domain/js_compat.dart' show jsNumText, jsParseFloat;
import '../common/sheet_toast.dart' show SheetToast;
import '../profile/profile_providers.dart' show profileProvider;
import 'home_controller.dart' show healthApiProvider;

@visibleForTesting
const goalValueKey = Key('goal-value'); // index.html:301 #water-goal-val

@visibleForTesting
const goalDecKey = Key('goal-dec'); // :299 #water-goal-dec

@visibleForTesting
const goalIncKey = Key('goal-inc'); // :302 #water-goal-inc

@visibleForTesting
const goalSaveKey = Key('goal-save'); // :307 #water-goal-save

@visibleForTesting
const goalCloseKey = Key('goal-close'); // :298 #goal-sheet-close

/// 打开喝水目标弹层（≙ openGoalSheet，app.js:470-475）。
/// [ref] 为调用页（常驻）WidgetRef：profileProvider invalidate 借它执行，
/// 与 openExerciseSheet hostRef 定式同构。
Future<void> openGoalSheet(
  BuildContext context,
  WidgetRef ref, {
  required num goalMl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(Tokens.radiusSheet),
      ),
    ),
    builder: (_) => _GoalSheet(hostRef: ref, goalMl: goalMl),
  );
}

class _GoalSheet extends ConsumerStatefulWidget {
  const _GoalSheet({required this.hostRef, required this.goalMl});

  final WidgetRef hostRef;
  final num goalMl;

  @override
  ConsumerState<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<_GoalSheet> {
  late final TextEditingController _ctl;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: _fmt(widget.goalMl)); // :473 预填
    // 失焦归一 ≙ bindStepperNorm 的 change/blur 双绑（app.js:1646-1647）
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _normField();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _toastEntry?.remove(); // 层内 toast 随层销毁（成功 toast 走 SnackBar 不受影响）
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// JS Number 串形（整值去 .0），预填/步进/归一共用
  static String _fmt(num v) => jsNumText(v);

  /// bindStepperNorm 归一（app.js:1639-1644 + :1653-1654 after 支）：
  /// NaN→min → clamp [800,3000] → 四舍五入对齐 200 整数倍。
  /// 解析走 jsParseFloat 前缀语义 ≙ H5 parseFloat（M6-T7 评审 F2：
  /// "1600." JS=1600、num.tryParse=null→800 分歧已闭合）。
  void _normField() {
    double v = jsParseFloat(_ctl.text.trim());
    if (v.isNaN) v = waterGoalMin.toDouble(); // :1640 isNaN→min
    if (v > waterGoalMax) v = waterGoalMax.toDouble(); // :1641 Math.min
    if (v < waterGoalMin) v = waterGoalMin.toDouble(); // :1641 Math.max
    v = ((v / waterCupMl).round() * waterCupMl).toDouble(); // :1654 Math.round(v/200)*200
    _ctl.text = _fmt(v);
  }

  /// bumpGoal（≙ app.js:476-483 逐字）：±200 截断，顶格值不动 + 边界 toast
  void _bump(int dir) {
    final cur = num.tryParse(_ctl.text.trim()) ?? 0; // Number('')→0 近似
    var next = cur + dir * waterCupMl;
    if (next > waterGoalMax) next = waterGoalMax; // Math.min(WATER_GOAL_MAX,·)
    if (next < waterGoalMin) next = waterGoalMin; // Math.max(WATER_GOAL_MIN,·)
    _ctl.text = _fmt(next);
    if (next == cur) {
      // :480 dir>0 ? '最大 3000ml' : '最小 800ml'（逐字）
      _toastInSheet(dir > 0 ? '最大 ${waterGoalMax}ml' : '最小 ${waterGoalMin}ml');
    }
  }

  /// 层内 toast（≙ H5 #toast z-index 恒在弹层之上）：Overlay 挂在弹层路由同
  /// 级 Overlay → 盖过弹层本体。目检 07b 实证 SnackBar 方案会被弹层遮挡且
  /// 经 ScaffoldMessenger 广播到下层首页 Scaffold 出现双份，故层内提示走
  /// OverlayEntry（成功 toast 在关层后走 SnackBar，与首页族一致）。
  OverlayEntry? _toastEntry;
  void _toastInSheet(String msg) {
    final overlay = Overlay.of(context);
    _toastEntry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => SheetToast(
        msg: msg,
        onDone: () {
          if (entry.mounted) entry.remove();
          if (identical(_toastEntry, entry)) _toastEntry = null;
        },
      ),
    );
    _toastEntry = entry;
    overlay.insert(entry);
  }

  /// 保存（≙ app.js:484-493）：await setWaterGoal → 关层 → invalidate → toast
  Future<void> _save() async {
    _normField(); // ≙ 按钮点击先触发输入框 change/blur（浏览器时序近似）
    final ml = num.tryParse(_ctl.text.trim()) ?? 0; // :487 Number(value)
    final messenger = ScaffoldMessenger.of(context);
    final hostRef = widget.hostRef;
    try {
      final res = await hostRef.read(healthApiProvider).setWaterGoal(ml);
      hostRef.invalidate(profileProvider); // goal 行刷新 + 「我的」页联动
      if (mounted) Navigator.of(context).pop(); // :490 closeSheet（成功才关）
      // :492 「喝水目标已设为 {waterGoalMl}ml」——以回包为准（云截断回显）；
      // 层已关，走首页 Scaffold 的 SnackBar（hideCurrent 先清失败残留同族）
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '喝水目标已设为 ${jsNumText((res['waterGoalMl'] as num?) ?? ml)}ml',
            ),
          ),
        );
    } catch (e) {
      // 差异登记：H5 无 catch → 静默层开；Flutter 通知失败，层同样不关
      // F1（M6-T7 评审）：与成功支 :157 对称的 mounted 守卫——在途关层后
      // Overlay.of(deactivated context) 会抛未处理异步错
      if (!mounted) return;
      _toastInSheet('同步失败：${e is ApiException ? e.message : '网络异常'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Tokens.sp5,
            Tokens.sp3,
            Tokens.sp5,
            Tokens.sp4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // .sheet-head：标题「喝水目标」+ ✕（index.html:296-299）
              Row(
                children: [
                  const Text(
                    '喝水目标',
                    style: TextStyle(
                      fontSize: Tokens.textLg,
                      fontWeight: FontWeight.w800,
                      color: Tokens.ink,
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    label: '关闭', // :299 aria-label 逐字
                    button: true,
                    child: GestureDetector(
                      key: goalCloseKey,
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(Tokens.sp1),
                        child: Text(
                          '✕',
                          style: TextStyle(
                            fontSize: Tokens.textMd,
                            color: Tokens.ink3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // .goal-stepper（:300-303；margin --sp-5 0 --sp-3）
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  Tokens.sp5,
                  0,
                  Tokens.sp3,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _stepperBtn(
                      goalDecKey,
                      '−',
                      '减少 ${waterCupMl}ml',
                      () => _bump(-1),
                    ), // :299 aria
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Tokens.sp2,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          SizedBox(
                            width: 120, // .stepper-input 96px 系 css font-display 窄数字；
                            // Flutter 默认字体 34px 四位数字实测 ~100px+，96 会裁尾
                            // （目检 05/06 实证），放宽到 120（R4 版式修正）
                            child: Semantics(
                              label: '喝水目标 ml', // :301 aria-label 逐字
                              child: TextField(
                                controller: _ctl,
                                focusNode: _focus,
                                key: goalValueKey,
                                textAlign: TextAlign.center,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                // M5-T7 定式：字符类过滤；非法/小数由归一兜底
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]'),
                                  ),
                                ],
                                style: const TextStyle(
                                  fontSize: 34, // .stepper-input font-size:34
                                  fontWeight: FontWeight.w600,
                                  color: Tokens.ink,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  counterText: '',
                                ),
                              ),
                            ),
                          ),
                          const Text(
                            'ml',
                            style: TextStyle(
                              fontSize: Tokens.textSm,
                              color: Tokens.ink3,
                            ),
                          ), // :301 <small>
                        ],
                      ),
                    ),
                    _stepperBtn(
                      goalIncKey,
                      '＋',
                      '增加 ${waterCupMl}ml',
                      () => _bump(1),
                    ), // :302 aria
                  ],
                ),
              ),
              // 范围注记（:305 逐字「每杯 200ml · 可设范围 800–3000ml」）
              Text(
                // 逐字「每杯 200ml · 可设范围 800–3000ml」（相邻字面量拼接避开 $ 后标识符歧义）
                '每杯 $waterCupMl'
                'ml · 可设范围 $waterGoalMin'
                '–$waterGoalMax'
                'ml',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: Tokens.textSm,
                  color: Tokens.ink3,
                ),
              ),
              const SizedBox(height: Tokens.sp4), // :307 btn margin-top --sp-4
              FilledButton(
                key: goalSaveKey,
                onPressed: _save,
                child: const Text('保存目标'), // :307 逐字
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// .stepper-btn（screens.css:364-368）：48 圆、surface 底、shadow-card
  Widget _stepperBtn(
    Key key,
    String glyph,
    String semantics,
    VoidCallback onTap,
  ) {
    return Semantics(
      label: semantics, // aria-label 减少/增加 200ml
      button: true,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Tokens.surface,
            shape: BoxShape.circle,
            boxShadow: Tokens.shadowCard,
          ),
          child: Text(
            glyph,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Tokens.primaryDeep,
            ),
          ),
        ),
      ),
    );
  }
}
