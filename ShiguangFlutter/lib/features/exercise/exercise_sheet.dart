// ShiguangFlutter/lib/features/exercise/exercise_sheet.dart
// 记运动弹层 + 删除确认弹层（M6-T2）。行为权威源 js/app.js:1756-1852 +
// index.html:415-434（exercise-sheet DOM）+ js/state.js:18（初值 run/5）。
// 逐字口径：
// - chips 点选重置量（:1784-1791）：km→5 / rep→10 / 其余→20；选中项即 currentLib。
// - 步进（:1792-1806）：step km 0.5 其余 5；dec 下限=step（Number(val)||step 再
//   Math.max(step,·-step)），inc 上限 km100/rep2000/min300（Math.min 静默——
//   顶格无 toast，简报「顶格 toast」条按裁定废弃对齐 H5）；toFixed(1) 走 jsFixed1。
// - 预览（:1761-1769）：「预计消耗 <b>N</b> kcal」，label 行 距离|数量|时长 +
//   单位后缀（exerciseAmountLabel）；体重 profileProvider.body.weightKg ?? 55。
//   R4 差异：手输非法值 H5 预览显示 NaN、Flutter 按 0 计（格式化差异不改行为）。
// - 保存（:1807-1830）：amount 以输入框为准（Number()||state 兜底）；kcal 为 0
//   →「请先设置运动量」不发请求不关层；正常 → 先关层（≙ :1818 乐观即关）再走
//   addExerciseRecord（toast 经 host ScaffoldMessenger，成功/失败文案见控制器）。
// - 删除确认（:1833 showConfirm）：confirmDeleteExercise 复刻 record_screen
//   删餐确认 AlertDialog 样式；文案「确认删除」「删除后无法恢复，确定要删除这
//   条运动吗？」逐字；取消/点外回 false 零请求（:1834）。
// openExerciseSheet 的 [ref] 来自常驻调用页（T3 首页）：保存即关层，弹层自身
// ref 随路由销毁，写链（invalidate）必须借 hostRef——这是简报签名带 ref 的原因。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/constants.dart' show Exercise, exerciseLib;
import '../../domain/exercise.dart'
    show exerciseAmountLabel, exerciseKcalOf;
import '../../domain/js_compat.dart' show jsFixed1;
import '../profile/profile_providers.dart' show profileProvider;
import 'exercise_controller.dart'
    show addExerciseRecord, exerciseWeightKg;

@visibleForTesting
const exAmountKey = Key('ex-amount'); // index.html:428 #exercise-amount-val

@visibleForTesting
const exDecKey = Key('ex-dec'); // :427 #exercise-amount-dec

@visibleForTesting
const exIncKey = Key('ex-inc'); // :429 #exercise-amount-inc

@visibleForTesting
const exSaveKey = Key('ex-save'); // :433 #exercise-save

@visibleForTesting
const exCloseKey = Key('ex-close'); // :421 #exercise-sheet-close

@visibleForTesting
const exPreviewKey = Key('ex-preview'); // :432 #exercise-kcal-preview

@visibleForTesting
Key exChipKey(String key) => Key('ex-chip-$key'); // :1759 data-xkey

/// 打开记运动弹层（≙ openExerciseSheet，app.js:1770-1776）。
/// [ref] 为调用页（常驻）WidgetRef，供保存链在弹层关闭后继续 invalidate。
Future<void> openExerciseSheet(
  BuildContext context,
  WidgetRef ref, {
  required String date,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(Tokens.radiusSheet)),
    ),
    builder: (_) => _ExerciseSheet(date: date, hostRef: ref),
  );
}

/// 删除确认弹层（≙ showConfirm('确认删除','删除后无法恢复，确定要删除这条运动吗？')，
/// app.js:1833）。样式复刻 record_screen 删餐确认（同款 AlertDialog + Tokens）。
Future<bool> confirmDeleteExercise(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Tokens.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusLg)),
      title: const Text('确认删除', // :1833 标题逐字
          style: TextStyle(
              fontSize: Tokens.textLg,
              fontWeight: FontWeight.w700,
              color: Tokens.ink)),
      content: const Text('删除后无法恢复，确定要删除这条运动吗？', // :1833 逐字
          style: TextStyle(fontSize: Tokens.textMd, color: Tokens.ink2)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消',
              style:
                  TextStyle(color: Tokens.ink3, fontSize: Tokens.textMd)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('确认删除',
              style: TextStyle(
                  color: Tokens.danger,
                  fontSize: Tokens.textMd,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok == true; // 点外/Esc 回 false ≙ H5 取消
}

class _ExerciseSheet extends ConsumerStatefulWidget {
  const _ExerciseSheet({required this.date, required this.hostRef});

  final String date;
  final WidgetRef hostRef;

  @override
  ConsumerState<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends ConsumerState<_ExerciseSheet> {
  // state.js:18 exerciseChosen:'run' / exerciseAmount:5（弹层每次新开都回默认，
  // ≙ H5 全局态不重置的近似——H5 重开会保留上次 chip 选择，R4 差异登记：
  // Flutter 弹层态随路由销毁，重开回默认档；量级=观感，请求体不受影响）
  String _chosen = exerciseLib.first.key;
  num _amountState = 5;

  final TextEditingController _amountCtl = TextEditingController(text: '5');

  /// currentLib（app.js:1725 find||EXERCISE_LIB[0] 同构）
  Exercise get _lib => exerciseLib.firstWhere(
        (l) => l.key == _chosen,
        orElse: () => exerciseLib.first,
      );

  @override
  void dispose() {
    _amountCtl.dispose();
    super.dispose();
  }

  /// JS 数字串形：整值去 .0（5.0→'5'），半步保留（4.5→'4.5'）
  static String _fmt(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : '$v';

  num _parseField() => num.tryParse(_amountCtl.text.trim()) ?? 0; // Number('')=0/NaN→0 近似

  void _apply(num amount) {
    setState(() {
      _amountState = amount;
      _amountCtl.text = _fmt(amount);
    });
  }

  /// chips 点选重置量（≙ :1784-1791）
  void _choose(String key) {
    final lib =
        exerciseLib.firstWhere((l) => l.key == key, orElse: () => exerciseLib.first);
    final amount = lib.unit == 'km' ? 5 : lib.unit == 'rep' ? 10 : 20; // :1787
    setState(() {
      _chosen = lib.key;
      _amountState = amount;
      _amountCtl.text = '$amount';
    });
  }

  /// 减（≙ :1792-1798 Math.max(step, +((Number(v)||step)-step).toFixed(1))）
  void _dec() {
    final step = _lib.unit == 'km' ? 0.5 : 5.0;
    final v = _parseField();
    final base = v == 0 ? step : v; // Number(val)||step（NaN/0 同落 step）
    var amount = jsFixed1(base - step);
    if (amount < step) amount = step; // Math.max
    _apply(amount);
  }

  /// 加（≙ :1799-1806 Math.min(max, +((Number(v)||0)+step).toFixed(1))；顶格静默）
  void _inc() {
    final lib = _lib;
    final step = lib.unit == 'km' ? 0.5 : 5.0;
    final max = lib.unit == 'km' ? 100.0 : lib.unit == 'rep' ? 2000.0 : 300.0;
    var amount = jsFixed1(_parseField() + step); // Number()||0：null/0 同落 0
    if (amount > max) amount = max; // Math.min
    _apply(amount);
  }

  void _toast(ScaffoldMessengerState m, String msg) {
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 保存（≙ :1807-1830）
  Future<void> _save() async {
    final lib = _lib;
    final v = num.tryParse(_amountCtl.text.trim());
    final amount = (v == null || v == 0) ? _amountState : v; // :1809 Number()||state
    final kcal =
        exerciseKcalOf(lib, amount, exerciseWeightKg(widget.hostRef)); // :1810-1811
    if (kcal == 0) {
      _toast(ScaffoldMessenger.of(context), '请先设置运动量'); // :1812 逐字，不发请求不关层
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(); // :1818 closeExerciseSheet（乐观即关，≙ H5 时序）
    // hostRef：弹层自身已随 pop 销毁，写链 invalidate 走常驻调用页的 ref
    await addExerciseRecord(
        widget.hostRef, widget.date, lib, amount, (m) => _toast(messenger, m));
  }

  @override
  Widget build(BuildContext context) {
    final lib = _lib;
    final (labName, labUnit) = exerciseAmountLabel(lib); // :1763-1765 label 行三型
    // 预览体重 watch 自身 ref：profile 在途→55 档，加载完自动刷新
    // （≙ :1766 state.body 就绪时序）；手输即刷 ≙ H5 步进点击时读框刷新（R4 增强）
    final wKg = ref.watch(profileProvider).maybeWhen(
        data: (p) {
          final b = p['body'];
          final w = b is Map ? b['weightKg'] : null;
          return w is num ? w : null;
        },
        orElse: () => null);
    final previewKcal = exerciseKcalOf(lib, _parseField(), wKg); // :1767-1768

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              Tokens.sp5, Tokens.sp3, Tokens.sp5, Tokens.sp4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题「记运动」+ ✕（index.html:419-422）
              Row(
                children: [
                  const Text('记运动',
                      style: TextStyle(
                          fontSize: Tokens.textLg,
                          fontWeight: FontWeight.w800,
                          color: Tokens.ink)),
                  const Spacer(),
                  Semantics(
                    label: '关闭', // :421 aria-label 逐字
                    button: true,
                    child: GestureDetector(
                      key: exCloseKey,
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(Tokens.sp1),
                        child: Text('✕',
                            style: TextStyle(
                                fontSize: Tokens.textMd, color: Tokens.ink3)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.sp3),
              // chips（:423 #exercise-chips，exerciseLib 全量，emoji+名）
              Wrap(
                spacing: Tokens.sp2,
                runSpacing: Tokens.sp2,
                children: [
                  for (final l in exerciseLib)
                    GestureDetector(
                      key: exChipKey(l.key),
                      onTap: () => _choose(l.key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Tokens.sp3, vertical: Tokens.sp2),
                        decoration: BoxDecoration(
                          color: l.key == _chosen
                              ? Tokens.primarySoft
                              : Tokens.surface2, // ≙ .ex-chip.active
                          borderRadius:
                              BorderRadius.circular(Tokens.radiusSm),
                          border: Border.all(
                            color: l.key == _chosen
                                ? Tokens.primary
                                : Tokens.line, // 选中态主色描边
                            width: l.key == _chosen ? 1.5 : 1,
                          ),
                        ),
                        child: Text('${l.emoji} ${l.name}',
                            style: TextStyle(
                              fontSize: Tokens.textSm,
                              fontWeight: l.key == _chosen
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: l.key == _chosen
                                  ? Tokens.primaryDeep
                                  : Tokens.ink2,
                            )),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Tokens.sp3),
              // 数量行（:424-431 label + −/输入/单位/＋）
              Text(labName,
                  style: const TextStyle(
                      fontSize: Tokens.textSm,
                      fontWeight: FontWeight.w700,
                      color: Tokens.ink)), // #exercise-amount-label
              const SizedBox(height: Tokens.sp1),
              Row(
                children: [
                  _stepperBtn(exDecKey, '−', '减少', _dec), // :427
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Tokens.sp2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              // T2 评审移交②：index.html:428 aria-label 逐字
                              label: '运动量',
                              child: TextField(
                                controller: _amountCtl,
                                key: exAmountKey,
                                textAlign: TextAlign.center,
                                keyboardType: const TextInputType
                                    .numberWithOptions(decimal: true),
                                // M5-T7 定式：字符类过滤，非法解析由步进/保存兜底
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.]')),
                                ],
                                onChanged: (_) => setState(() {}), // 预览实时刷
                                decoration: const InputDecoration(
                                    isDense: true, counterText: ''),
                              ),
                            ),
                          ),
                          const SizedBox(width: Tokens.sp1),
                          Text(labUnit, // #exercise-amount-unit
                              style: const TextStyle(
                                  fontSize: Tokens.textSm,
                                  color: Tokens.ink3)),
                        ],
                      ),
                    ),
                  ),
                  _stepperBtn(exIncKey, '＋', '增加', _inc), // :429
                ],
              ),
              const SizedBox(height: Tokens.sp3),
              // 预览「预计消耗 N kcal」（:432，数字加粗 ≙ <b>）
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                      fontSize: Tokens.textMd, color: Tokens.ink2),
                  children: [
                    const TextSpan(text: '预计消耗 '),
                    TextSpan(
                        text: '$previewKcal',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, color: Tokens.ink)),
                    const TextSpan(text: ' kcal'),
                  ],
                ),
                key: exPreviewKey,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Tokens.sp4),
              // 保存通栏钮（:433「保存记录」逐字；主题已 Size(0,52) 高）
              FilledButton(
                key: exSaveKey,
                onPressed: _save,
                child: const Text('保存记录'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepperBtn(Key key, String label, String semantics,
      VoidCallback onTap) {
    return Semantics(
      label: semantics, // aria-label 减少/增加 逐字
      button: true,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Tokens.surface2, // ≙ .stepper-btn
            borderRadius: BorderRadius.circular(Tokens.radiusSm),
            border: Border.all(color: Tokens.line),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: Tokens.textLg,
                  fontWeight: FontWeight.w700,
                  color: Tokens.ink2)),
        ),
      ),
    );
  }
}
