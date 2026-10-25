// ShiguangFlutter/lib/features/profile/goal_edit_sheet.dart
// 目标体重编辑弹层（M7-T5；spec §4.3）。行为权威源 H5（文案逐字）：
// - openGoalEditSheet(js/app.js:1427-1432)：预填 `profile?.goal?.targetWeight
//   || 55`（falsy ≙ null/0 皆落 55）；
// - 常量 :1425：WEIGHT_STEP=0.5、WEIGHT_MIN=30、WEIGHT_MAX=150；
// - 步进 :1440-1451（goal-edit 专用 handler，非 bumpBodyVal）：
//   dec = Math.max(30, +(cur−0.5).toFixed(1))、inc = Math.min(150, +(cur+0.5)
//   .toFixed(1))；顶格值不动 + toast「最小 30 kg」/「最大 150 kg」（逐字，
//   含半角空格；与身体档案弹层「已到上限/下限」不同族）；
// - 失焦/回车归一 ≙ bindStepperNorm('#weight-goal-val',30,150,1)(:1652)：
//   parseFloat 前缀语义 NaN→30、clamp、+toFixed(1)（goal_sheet._normField 同款）；
// - 保存 :1453-1465：setGoal({targetWeight}) **单键**（≙ M7-T5 起 HealthApi
//   .setGoal 具名可选签名，null 键剥离）→ 本地 profileData.goal 回写 +
//   #goal-weight 刷新 + renderMetab ≙ invalidate(profileProvider)（单一事实源
//   =云端，重取回真值后代谢卡/ETA 联动）→ 关层 → toast「目标体重已更新」；
//   失败「保存失败：msg||网络异常」层不关（jsOr 口径，终审 Minor-1）。
// - DOM/文案 index.html:335-351：标题「编辑目标体重」、aria-label「关闭」/
//   「减少 0.5 kg」/「增加 0.5 kg」/「目标体重 kg」、hint
//   `体重范围 30–150 kg · 点数字可直接输入 · 热量目标由系统按档案自动计算`
//   （**en-dash U+2013 逐字**）、钮「保存目标」。
// 弹层结构抄 home/goal_sheet.dart 同族（stepper+输入+保存通栏）；层内提示走
// OverlayEntry/SheetToast（goal_sheet 07b 定式：SnackBar 被弹层遮挡且广播双份），
// 成功 toast 在关层后走 SnackBar。入口接线：body_profile_card 代谢卡目标体重行
// 「点击修改」（spec §4.3 裁定；≙ #btn-edit-goal，app.js:1031）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/js_compat.dart'
    show jsFixed1, jsNumber, jsNumText, jsOr, jsParseFloat;
import '../common/breathing_capsule.dart' show LoadingSpinner;
import '../common/sheet.dart' show showShiguangSheet;
import '../common/sheet_toast.dart' show SheetToast;
import '../home/home_controller.dart' show healthApiProvider;
import 'profile_providers.dart' show profileProvider;

/* ---------- 常量 ≙ js/app.js:1425（WEIGHT_STEP/MIN/MAX） ---------- */

const double _weightStep = 0.5;
const double _weightMin = 30;
const double _weightMax = 150;

/* ---------- 测试键（H5 id 同名，index.html:335-351） ---------- */

@visibleForTesting
const goalEditValueKey = Key('weight-goal-val');

@visibleForTesting
const goalEditDecKey = Key('weight-goal-dec');

@visibleForTesting
const goalEditIncKey = Key('weight-goal-inc');

@visibleForTesting
const goalEditSaveKey = Key('goal-edit-save');

@visibleForTesting
const goalEditCloseKey = Key('goal-edit-close');

/// 打开目标体重编辑弹层（≙ openGoalEditSheet，app.js:1427-1432）。
/// [ref] 为调用页（常驻）WidgetRef：profileProvider invalidate 借它执行，
/// 与 goal_sheet hostRef 定式同构。预填取打开时的 profile.goal.targetWeight
/// （在途/失败/0 ≙ H5 `|| 55` 兜底，:1429）。
Future<void> openGoalEditSheet(BuildContext context, WidgetRef ref) {
  final p = ref.read(profileProvider).value;
  final goal = (p?['goal'] as Map?)?['targetWeight'];
  final initial = (goal is num && goal != 0) ? goal.toDouble() : 55.0;
  return showShiguangSheet<void>(
    context,
    title: '编辑目标体重', // :339 逐字（M9-T8 起由 helper 标题行承载）
    closeKey: goalEditCloseKey, // :340 ✕ 键位透传（find.byKey 测试选择器不动）
    child: _GoalEditSheet(hostRef: ref, initial: initial),
  );
}

class _GoalEditSheet extends ConsumerStatefulWidget {
  const _GoalEditSheet({required this.hostRef, required this.initial});

  final WidgetRef hostRef;
  final double initial;

  @override
  ConsumerState<_GoalEditSheet> createState() => _GoalEditSheetState();
}

class _GoalEditSheetState extends ConsumerState<_GoalEditSheet> {
  late final TextEditingController _ctl = TextEditingController(
    text: jsNumText(widget.initial),
  ); // :1429 预填串形
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 失焦归一 ≙ bindStepperNorm 的 change/blur 双绑（app.js:1646-1647/:1652）
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _normField();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _toastEntry?.remove(); // 层内 toast 随层销毁
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// bindStepperNorm('#weight-goal-val',30,150,1)（app.js:1638-1644/:1652）：
  /// parseFloat 前缀语义 NaN→min → clamp → +toFixed(1)。
  void _normField() {
    double v = jsParseFloat(_ctl.text.trim());
    if (v.isNaN) v = _weightMin; // :1640 isNaN→min
    v = v.clamp(_weightMin, _weightMax).toDouble(); // :1641
    v = jsFixed1(v); // :1642 +v.toFixed(1)
    _ctl.text = jsNumText(v); // 串形：52.0 → '52'
  }

  /// 步进（≙ app.js:1440-1451 逐支）：dec 只 Math.max(30,·)、inc 只
  /// Math.min(150,·)（与 bumpBodyVal 双向 clamp 不同——照抄不"修正"）；
  /// 解析 Number() 全串语义（M6 终审 I1：'52.'→52；''→0，NaN 不可达——
  /// 字符类 [0-9.]，goal_sheet._bump 同款）。顶格值不动 + 边界 toast 逐字。
  void _bump(int dir) {
    final cur = (jsNumber(_ctl.text.trim()) ?? 0).toDouble();
    var next = jsFixed1(cur + dir * _weightStep); // +(cur±0.5).toFixed(1)
    if (dir < 0 && next < _weightMin) next = _weightMin; // :1442 Math.max
    if (dir > 0 && next > _weightMax) next = _weightMax; // :1448 Math.min
    _ctl.text = jsNumText(next);
    if (next == cur) {
      // :1444/:1450 逐字（含半角空格）。数字串形走 jsNumText ≙ JS 模板
      // `${WEIGHT_MIN}`（Dart double 30.0 直插会漂出「30.0 kg」）
      _toastInSheet(
        dir > 0
            ? '最大 ${jsNumText(_weightMax)} kg'
            : '最小 ${jsNumText(_weightMin)} kg',
      );
    }
  }

  /// 层内 toast（≙ H5 #toast z-index 恒在弹层之上；goal_sheet 07b 定式）
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

  /// 保存（≙ app.js:1453-1465）：setGoal **单键** {targetWeight} →
  /// invalidate profileProvider（≙ 本地回写 + #goal-weight + renderMetab）→
  /// 关层 → toast「目标体重已更新」；失败层不关 + 「保存失败：msg||网络异常」。
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    _normField(); // ≙ 按钮点击先触发输入框 change/blur（浏览器时序近似）
    final targetWeight = jsNumber(_ctl.text.trim()) ?? 0; // :1454 Number(value)
    final messenger = ScaffoldMessenger.of(context);
    final hostRef = widget.hostRef;
    try {
      await hostRef
          .read(healthApiProvider)
          .setGoal(targetWeight: targetWeight); // :1456 单键
      hostRef.invalidate(profileProvider); // :1457-1459 联动等价
      if (mounted) Navigator.of(context).pop(); // :1460 closeGoalEditSheet
      // :1461 逐字；层已关，走宿主 Scaffold 的 SnackBar
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('目标体重已更新')));
    } catch (e) {
      // :1463 层不关（toast 盖弹层 → 层内 OverlayEntry 通道）
      if (!mounted) return; // 在途关层守卫（goal_sheet F1 同款）
      _toastInSheet(
        '保存失败：${e is ApiException ? jsOr(e.message, '网络异常') : '网络异常'}',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // M9-T8：.sheet-head 标题行「编辑目标体重」+ ✕（index.html:338-341，
    // goalEditCloseKey 键位经 helper closeKey 透传）与内层 SafeArea 由
    // showShiguangSheet 承载，本地副本删除；顶部 sp3 内边距归零（原标题
    // 占位），说明→section 的 sp5 净距不变；viewInsets 包裹保留（键盘避让）。
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Tokens.sp5,
          0,
          Tokens.sp5,
          Tokens.sp4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // .goal-edit-section（:342-349）：label + stepper
            const Padding(
              padding: EdgeInsets.fromLTRB(0, Tokens.sp5, 0, Tokens.sp2),
              child: Text(
                '目标体重', // :343 逐字
                style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stepperBtn(
                  goalEditDecKey,
                  '−',
                  '减少 0.5 kg', // :345 aria 逐字
                  () => _bump(-1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Tokens.sp2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      SizedBox(
                        width: 120, // 同 goal_sheet :259 口径（默认字体宽于 css）
                        child: Semantics(
                          label: '目标体重 kg', // :346 aria-label 逐字
                          child: TextField(
                            controller: _ctl,
                            focusNode: _focus,
                            key: goalEditValueKey,
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
                        'kg', // :346 <small>kg</small>
                        style: TextStyle(
                          fontSize: Tokens.textSm,
                          color: Tokens.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
                _stepperBtn(
                  goalEditIncKey,
                  '＋',
                  '增加 0.5 kg', // :347 aria 逐字
                  () => _bump(1),
                ),
              ],
            ),
            const SizedBox(height: Tokens.sp3),
            // hint（:350 逐字；en-dash U+2013「30–150」不折不改横线）
            const Text(
              '体重范围 30–150 kg · 点数字可直接输入 · 热量目标由系统按档案自动计算',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3),
            ),
            const SizedBox(height: Tokens.sp4), // :351 btn margin-top --sp-4
            FilledButton(
              key: goalEditSaveKey,
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                disabledBackgroundColor: Tokens.primaryDeep.withValues(alpha: .72),
                disabledForegroundColor: Colors.white,
              ),
              child: _saving
                  ? const LoadingSpinner()
                  : const Text('保存目标'), // :351 逐字
            ),
          ],
        ),
      ),
    );
  }

  /// .stepper-btn（同 goal_sheet._stepperBtn：48 圆、surface 底、shadow-card）
  Widget _stepperBtn(
    Key key,
    String glyph,
    String semantics,
    VoidCallback onTap,
  ) {
    return Semantics(
      label: semantics, // aria-label 减少/增加 0.5 kg
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
