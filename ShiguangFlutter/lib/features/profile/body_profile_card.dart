// ShiguangFlutter/lib/features/profile/body_profile_card.dart
// M5 Task 6：「我的」页身体参数卡——六值展示 + 代谢明细 + 编辑弹层 + 保存链。
// 接线次序（T5 备忘）：资料头 → 体重卡 → **本卡** → 提醒卡 → 退出。
// 行为权威源 H5（文案逐字）：
// - renderBodyCard(js/app.js:1571-1579)：身高 `${heightCm} cm`、体重
//   `${weightKg} kg`、BMI Number(bmi).toFixed(1)、年龄 `${age} 岁`、
//   性别 male?男:女、活动量 (ACTIVITY[a]||light).label。
// - renderMetab(:1581-1609)：tw=profileData.goal.targetWeight（:1583）；
//   BMR/TDEE/建议摄入/缺口四数 + 公式注记（:1598-1601）+ 标题右 note
//   「基准目标 suggest kcal」（:1605 非含运动支）+ etaText/rangeText 原文。
//   **降级登记**：H5 传 state.actualDeficit（localStorage 近 7 天实际缺口），
//   本任务 actualInfo 恒 null=预设缺口口径（缺口行注记「预设缺口 500」逐字
//   取 :1601 非 useActual 支；M6 若做实际缺口再补）。H5 第五行「今日运动」
//   依赖首页运动记录 state，本卡不接线（ex=0 恒等支），差异登记报告。
// - openBodySheet/bumpBodyVal/bindStepperNorm(:1612-1666)：弹层预填当前档案；
//   身高 ±1 闸 100-250、体重 ±0.5 闸 30-200（bump 定 1 位小数 :1663-1664，
//   保存输入 norm 定 2 位 :1650）、年龄 ±1 闸 10-100；bump 钳制后不变 →
//   toast「已到上限/已到下限」（:1633 逐字；与体重卡 _bump 同型，就地同实现）。
// - body-save(:1680-1703)：收集六字段 + bmi=+(W/(H/100)^2).toFixed(1)（:1690）
//   → **先关弹层再 await**（:1695 次序）→ updateProfile(b) → syncTarget →
//   toast「身体档案已保存」（:1699）；catch → 「已本地保存：+ (e.message||
//   '网络异常')」（:1701 逐字）。
// - syncTarget(:1706-1718)：computeMetabolism(body, tw).suggest ≠ goal.dailyKcal
//   才 PUT /user/goal {dailyKcal, targetWeight}（tw 缺省回落当前体重，简报裁定
//   `tw ?? weightKg`）；无论成败重取资料（≙ H5 本地已生效+下次加载再同步，
//   Flutter 单一事实源=云端，invalidate profileProvider/summaryProvider）。
// 主题债（T5 评审点名）：theme.dart filledButtonTheme.minimumSize 宽=∞——本文件
// 所有 FilledButton 均为 Column 通栏位，不进 Row 非 flex 子。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/constants.dart' show activity;
import '../../domain/js_compat.dart' show jsFixed1, jsNumText;
import '../../domain/metabolism.dart' show computeMetabolism;
import '../../domain/models.dart' show Body;
import '../home/home_controller.dart'
    show healthApiProvider, summaryProvider;
import 'profile_providers.dart' show profileProvider;

/* ---------- 测试键（H5 id 同名，index.html:354-413） ---------- */

@visibleForTesting
const bodyHeightValKey = Key('height-val');
@visibleForTesting
const bodyHeightDecKey = Key('height-dec');
@visibleForTesting
const bodyHeightIncKey = Key('height-inc');
@visibleForTesting
const bodyWeightValKey = Key('weight-val');
@visibleForTesting
const bodyWeightDecKey = Key('weight-dec');
@visibleForTesting
const bodyWeightIncKey = Key('weight-inc');
@visibleForTesting
const bodyAgeValKey = Key('age-val');
@visibleForTesting
const bodyAgeDecKey = Key('age-dec');
@visibleForTesting
const bodyAgeIncKey = Key('age-inc');
@visibleForTesting
const bodySaveKey = Key('body-save');

/// JS Number→JSON 串形：整数值落 int（168.0 → 168，同 js JSON.stringify）。
num _jsNumOut(num v) =>
    v is double && v == v.truncateToDouble() && v.abs() < 1e15 ? v.toInt() : v;

/// profile.body → Body（简报 Step 2 逐字取法；缺字段回落 Body.fromMap 默认档）
Body _bodyOf(Map<String, dynamic> p) =>
    Body.fromMap(((p['body'] ?? const {}) as Map).cast<String, Object?>());

/// 保存链（≙ body-save :1696-1702 + syncTarget :1706-1718；简报裁定签名：
/// toast 由调用方传页面 _toast/弹层宿主 toast，不做 ref 扩展）。
/// 次序：updateProfile(bodyMap) → suggest≠goal.dailyKcal 才 setGoal →
/// toast；失败仍走 toast「已本地保存：…」；无论成败 finally 双 invalidate
/// （profileProvider 重取回真值；summaryProvider family 整族——首页环目标联动）。
Future<void> saveBodyProfile(WidgetRef ref, Map<String, Object?> bodyMap,
    void Function(String) toast) async {
  final api = ref.read(healthApiProvider);
  final profile = ref.read(profileProvider).value ?? const <String, dynamic>{};
  final goal = (profile['goal'] as Map?)?.cast<String, dynamic>() ?? const {};
  final tw = (goal['targetWeight'] as num?)?.toDouble();
  final body = Body.fromMap(bodyMap);
  try {
    await api.updateProfile(bodyMap.cast<String, dynamic>()); // :1697
    // :1709 computeMetabolism(state.body, tw)——第三参省略 ≙ Flutter 传 null
    final m = computeMetabolism(body, tw, null);
    if (m.suggest != (goal['dailyKcal'] as num?)) {
      // :1715 setGoal({dailyKcal: suggest, targetWeight: tw})；tw 缺省回落当前体重
      await api.setGoal(m.suggest, tw ?? body.weightKg.toDouble());
    }
    toast('身体档案已保存'); // :1699 逐字
  } catch (e) {
    final msg = e is ApiException ? e.message : '';
    // :1701 `toast('已本地保存：' + (e.message || '网络异常'))`（空串 falsy 兜底）
    toast('已本地保存：${msg.isEmpty ? '网络异常' : msg}');
  } finally {
    ref.invalidate(profileProvider);
    ref.invalidate(summaryProvider); // family 整族失效（首页环目标联动）
  }
}

/// 身体参数卡（六值 + 代谢明细；点卡开编辑弹层 ≙ #body-card click :1658）
class BodyProfileCard extends ConsumerWidget {
  const BodyProfileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final p = profile.value;
    return Semantics(
      label: '编辑身体档案', // index.html:202 aria-label 逐字
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context, ref),
        child: Container(
          padding: const EdgeInsets.all(Tokens.sp4),
          decoration: BoxDecoration(
            color: Tokens.surface,
            borderRadius: BorderRadius.circular(Tokens.radiusLg),
            boxShadow: Tokens.shadowCard,
          ),
          child: p == null
              ? (profile is AsyncError
                  // 占位自拟（简报无字面；失败可点重试，同 T5 头部口径）
                  ? const Text('身体档案获取失败，点击重试',
                      style: TextStyle(
                          fontSize: Tokens.textMd, color: Tokens.danger))
                  : const Text('…',
                      style: TextStyle(
                          fontSize: Tokens.textMd, color: Tokens.ink3)))
              : _cardBody(p),
        ),
      ),
    );
  }

  /// openBodySheet（:1612-1622）：档案未加载（≙ !b）点开 no-op；失败态点击=重试。
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final p = ref.read(profileProvider).value;
    if (p == null) {
      ref.invalidate(profileProvider);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final bodyMap = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true, // 表单长，可滚动（目检项）
      backgroundColor: Tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Tokens.radiusSheet)),
      ),
      builder: (_) => _BodyProfileSheet(initial: _bodyOf(p)),
    );
    if (bodyMap == null) return; // ✕/外触关闭：H5 closeBodySheet 无保存动作
    await saveBodyProfile(ref, bodyMap, (msg) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(msg), behavior: SnackBarBehavior.floating));
    });
  }

  // ---- 卡面（renderBodyCard + renderMetab，版式 R4 自主） ----

  Widget _cardBody(Map<String, dynamic> p) {
    final b = _bodyOf(p);
    final goal = (p['goal'] as Map?)?.cast<String, dynamic>() ?? const {};
    final tw = (goal['targetWeight'] as num?)?.toDouble();
    final m = computeMetabolism(b, tw, null); // 降级：actualInfo=null 预设口径
    final af = (activity[b.activity] ?? activity['light']!).f;
    final bmiShown = (b.bmi ??
            b.weightKg / math.pow(b.heightCm / 100, 2)) // 云端缺 bmi 时补算（防御）
        .toDouble()
        .toStringAsFixed(1); // :1575 Number(bmi).toFixed(1)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: const [
            Text('身体档案', // index.html:203 逐字
                style: TextStyle(
                    fontSize: Tokens.textMd,
                    fontWeight: FontWeight.w700,
                    color: Tokens.ink)),
            Spacer(),
            Text('点击编辑 ›', // :203 .more 逐字
                style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3)),
          ],
        ),
        const SizedBox(height: Tokens.sp3),
        Row(children: [
          Expanded(child: _stat('身高', jsNumText(b.heightCm), ' cm')), // :1573
          Expanded(child: _stat('体重', jsNumText(b.weightKg), ' kg')), // :1574
          Expanded(child: _stat('BMI', bmiShown)), // :1575
        ]),
        const SizedBox(height: Tokens.sp2),
        Row(children: [
          Expanded(child: _stat('年龄', jsNumText(b.age), ' 岁')), // :1576
          Expanded(
              child: _stat(
                  '性别', b.gender == 'male' ? '男' : '女')), // :1577
          Expanded(
              child: _stat(
                  '活动量',
                  (activity[b.activity] ?? activity['light']!).label)), // :1578
        ]),
        const SizedBox(height: Tokens.sp3),
        const Divider(height: 1, color: Tokens.line),
        const SizedBox(height: Tokens.sp3),
        Row(
          children: [
            const Expanded(
              child: Text('代谢与减脂计划', // index.html:215 逐字
                  style: TextStyle(
                      fontSize: Tokens.textMd,
                      fontWeight: FontWeight.w700,
                      color: Tokens.ink)),
            ),
            Text('基准目标 ${jsNumText(m.suggest)} kcal', // :1605 非含运动支逐字
                style:
                    const TextStyle(fontSize: Tokens.textXs, color: Tokens.ink3)),
          ],
        ),
        const SizedBox(height: Tokens.sp2),
        _metabLine(
            '基础代谢 BMR', // index.html:217 逐字
            '${jsNumText(m.bmr)} kcal',
            '10×${jsNumText(b.weightKg)}+6.25×${jsNumText(b.heightCm)}−5×${jsNumText(b.age)}${b.gender == 'male' ? '+5' : '−161'}'), // :1598
        _metabLine(
            '每日消耗 TDEE', // :218
            '${jsNumText(m.tdee)} kcal',
            'BMR×系数${jsNumText(af)}'), // :1599 ex=0 支
        _metabLine(
            '今日建议摄入', // :219
            '${jsNumText(m.suggest)} kcal',
            '消耗${jsNumText(m.tdee)}−缺口${jsNumText(m.realDeficit)}'), // :1600 ex=0 支
        _metabLine(
            '每日缺口', // :220
            '${jsNumText(m.effDeficit)} kcal',
            '预设缺口 ${jsNumText(m.realDeficit)}'), // :1601 非 useActual 支（降级标注）
        const SizedBox(height: Tokens.sp2),
        Text(m.etaText, // :1606-1608 原文
            style: const TextStyle(fontSize: Tokens.textXs, color: Tokens.ink2)),
        const SizedBox(height: Tokens.sp1),
        Text(m.rangeText, // :1608 第二行 opacity .85 位 → ink3
            style: const TextStyle(fontSize: Tokens.textXs, color: Tokens.ink3)),
      ],
    );
  }

  Widget _stat(String label, String value, [String unit = '']) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: Tokens.textXs, color: Tokens.ink2)),
        const SizedBox(height: Tokens.sp1),
        Text.rich(TextSpan(
            style: const TextStyle(
                fontSize: Tokens.textLg,
                fontWeight: FontWeight.w700,
                color: Tokens.ink),
            children: [
              TextSpan(text: value),
              if (unit.isNotEmpty)
                TextSpan(
                    text: unit, // `<small> cm</small>` ≙ 小字单位
                    style: const TextStyle(
                        fontSize: Tokens.textXs,
                        fontWeight: FontWeight.w400,
                        color: Tokens.ink3)),
            ])),
      ],
    );
  }

  Widget _metabLine(String label, String value, String formula) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.sp2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: Tokens.textSm, color: Tokens.ink2)),
                Text(formula, // 公式注记（:1598-1601 逐字段）
                    style: const TextStyle(
                        fontSize: Tokens.textXs, color: Tokens.ink3)),
              ],
            ),
          ),
          const SizedBox(width: Tokens.sp2),
          Text(value,
              style: const TextStyle(
                  fontSize: Tokens.textMd,
                  fontWeight: FontWeight.w700,
                  color: Tokens.ink)),
        ],
      ),
    );
  }
}

/* ---------- 编辑弹层（≙ #body-sheet，index.html:354-413 + app.js:1612-1703） ---------- */

class _BodyProfileSheet extends StatefulWidget {
  const _BodyProfileSheet({required this.initial});

  final Body initial;

  @override
  State<_BodyProfileSheet> createState() => _BodyProfileSheetState();
}

class _BodyProfileSheetState extends State<_BodyProfileSheet> {
  // openBodySheet :1614-1616：预填当前档案（JS input.value=Number 的串形）
  late final TextEditingController _heightCtl =
      TextEditingController(text: jsNumText(widget.initial.heightCm));
  late final TextEditingController _weightCtl =
      TextEditingController(text: jsNumText(widget.initial.weightKg));
  late final TextEditingController _ageCtl =
      TextEditingController(text: jsNumText(widget.initial.age));

  // :1617-1619 三组选择器按值点亮；档案值不在选项集时不点亮任何项，
  // 保存走 :1686-1688 缺省兜底（female/light/500）。late：初始化器读 widget。
  late String? _gender =
      const ['female', 'male'].contains(widget.initial.gender)
          ? widget.initial.gender
          : null;
  late String? _activityKey =
      activity.containsKey(widget.initial.activity)
          ? widget.initial.activity
          : null;
  late num? _deficit = const [300, 500, 750].contains(widget.initial.deficit)
      ? widget.initial.deficit
      : null;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  /// bumpBodyVal（:1627-1634）：clamp 到 [min,max]，体重定 1 位小数；
  /// 钳制后不变 → 「已到上限/已到下限」（逐字，与体重卡 _bump 就地同实现）。
  void _bump(TextEditingController ctl, double delta, double min, double max,
      {bool fixed1 = false}) {
    final cur = double.tryParse(ctl.text.trim()) ?? 0; // Number(el.value)：''→0
    var next = (cur + delta).clamp(min, max).toDouble();
    if (fixed1) next = jsFixed1(next); // :1631 +next.toFixed(1)
    ctl.text = jsNumText(next);
    if (next == cur) _toast(delta > 0 ? '已到上限' : '已到下限'); // :1633 逐字
  }

  /// bindStepperNorm（:1636-1648）：NaN→min；clamp；定 fixed 位小数（H5 于
  /// change/blur 归一，Flutter 收敛到保存收集时——净效果同：点保存先失焦）。
  double _norm(TextEditingController ctl, double min, double max, int fixed) {
    var v = double.tryParse(ctl.text.trim());
    if (v == null || v.isNaN) v = min; // :1640 isNaN→min
    v = v.clamp(min, max).toDouble();
    v = double.parse(v.toStringAsFixed(fixed)); // :1642 +v.toFixed(fixed)
    ctl.text = jsNumText(v);
    return v;
  }

  /// body-save 收集面（:1681-1690）：六字段 + bmi；bmi 在此算（简报裁定）。
  Map<String, Object?> _collect() {
    final h = _norm(_heightCtl, 100, 250, 0); // :1649（bump 后 :1661-1662 ±1）
    final w = _norm(_weightCtl, 30, 200, 2); // :1650
    final a = _norm(_ageCtl, 10, 100, 0); // :1651
    return <String, Object?>{
      'heightCm': h.toInt(), // fixed=0 归一后恒整（JS Number 串形）
      'weightKg': _jsNumOut(w),
      'age': a.toInt(),
      'gender': _gender ?? 'female', // :1686 无选中兜底
      'activity': _activityKey ?? 'light', // :1687
      'deficit': _deficit ?? 500, // :1688
      'bmi': _jsNumOut(jsFixed1(w / math.pow(h / 100, 2))), // :1690
    };
  }

  @override
  void dispose() {
    _heightCtl.dispose();
    _weightCtl.dispose();
    _ageCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          // 表单长（六组控件+保存）：限高可滚动（R4 关注滚动可用性）
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                Tokens.sp5, Tokens.sp3, Tokens.sp5, Tokens.sp4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('身体档案', // index.html:359 逐字
                        style: TextStyle(
                            fontSize: Tokens.textLg,
                            fontWeight: FontWeight.w800,
                            color: Tokens.ink)),
                    const Spacer(),
                    Semantics(
                      label: '关闭', // :360 aria-label 逐字
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(Tokens.sp1),
                          child: Text('✕',
                              style: TextStyle(
                                  fontSize: Tokens.textMd,
                                  color: Tokens.ink3)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.sp3),
                _stepper(
                    label: '身高', // :363 逐字
                    ctl: _heightCtl,
                    fieldKey: bodyHeightValKey,
                    decKey: bodyHeightDecKey,
                    incKey: bodyHeightIncKey,
                    unit: 'cm',
                    decAria: '减少 1cm', // :365 逐字
                    incAria: '增加 1cm', // :367 逐字
                    delta: 1,
                    min: 100,
                    max: 250,
                    integer: true),
                const SizedBox(height: Tokens.sp3),
                _stepper(
                    label: '体重', // :371 逐字
                    ctl: _weightCtl,
                    fieldKey: bodyWeightValKey,
                    decKey: bodyWeightDecKey,
                    incKey: bodyWeightIncKey,
                    unit: 'kg',
                    decAria: '减少 0.5kg', // :373 逐字
                    incAria: '增加 0.5kg', // :375 逐字
                    delta: 0.5,
                    min: 30,
                    max: 200,
                    bumpFixed1: true), // :1663-1664 fixed=1
                const SizedBox(height: Tokens.sp3),
                _stepper(
                    label: '年龄', // :379 逐字
                    ctl: _ageCtl,
                    fieldKey: bodyAgeValKey,
                    decKey: bodyAgeDecKey,
                    incKey: bodyAgeIncKey,
                    unit: '岁',
                    decAria: '减少 1岁', // :381 逐字
                    incAria: '增加 1岁', // :383 逐字
                    delta: 1,
                    min: 10,
                    max: 100,
                    integer: true),
                const SizedBox(height: Tokens.sp2),
                const Text(
                    '点中间数字可直接输入（体重支持一位小数），也可用两侧 ＋/−', // :386 逐字
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: Tokens.textXs, color: Tokens.ink3)),
                const SizedBox(height: Tokens.sp3),
                const Text('性别', style: _label), // :388 逐字
                const SizedBox(height: Tokens.sp2),
                Row(
                  children: [
                    Expanded(
                        child: _seg('女', _gender == 'female', // :390 逐字
                            () => setState(() => _gender = 'female'),
                            key: const Key('gender-female'))),
                    const SizedBox(width: Tokens.sp2),
                    Expanded(
                        child: _seg('男', _gender == 'male', // :391 逐字
                            () => setState(() => _gender = 'male'),
                            key: const Key('gender-male'))),
                  ],
                ),
                const SizedBox(height: Tokens.sp3),
                const Text('活动量', style: _label), // :395 逐字
                const SizedBox(height: Tokens.sp2),
                // activity chips 五档，label 用 constants 现成（:396-402）
                Wrap(
                  spacing: Tokens.sp2,
                  runSpacing: Tokens.sp2,
                  children: [
                    for (final k in activity.keys)
                      _seg(
                          activity[k]!.label,
                          _activityKey == k,
                          () => setState(() => _activityKey = k),
                          key: Key('activity-$k')),
                  ],
                ),
                const SizedBox(height: Tokens.sp3),
                const Text('每日热量缺口', style: _label), // :405 逐字
                const SizedBox(height: Tokens.sp2),
                Row(
                  children: [
                    for (final (i, d) in const [300, 500, 750].indexed) ...[
                      if (i > 0) const SizedBox(width: Tokens.sp2),
                      Expanded(
                        child: _seg(
                            // :407-409 逐字
                            switch (d) {
                              300 => '温和 300',
                              500 => '标准 500',
                              _ => '积极 750',
                            },
                            _deficit == d,
                            () => setState(() => _deficit = d),
                            key: Key('deficit-$d')),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Tokens.sp4),
                FilledButton( // :412 btn-primary 通栏（主题宽=∞ 债安全位）
                    key: bodySaveKey,
                    onPressed: () =>
                        Navigator.of(context).pop(_collect()), // 先关层再存（:1695）
                    child: const Text('保存档案')), // :412 逐字
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _label = TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2);

  Widget _stepper({
    required String label,
    required TextEditingController ctl,
    required Key fieldKey,
    required Key decKey,
    required Key incKey,
    required String unit,
    required String decAria,
    required String incAria,
    required double delta,
    required double min,
    required double max,
    bool bumpFixed1 = false,
    bool integer = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _label),
        const SizedBox(height: Tokens.sp2),
        Row(
          children: [
            _stepBtn('−', decKey, decAria,
                () => _bump(ctl, -delta, min, max, fixed1: bumpFixed1)),
            Expanded(
              child: TextField(
                key: fieldKey,
                controller: ctl,
                keyboardType: integer
                    ? const TextInputType.numberWithOptions(signed: true)
                    : const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: Tokens.textLg,
                    fontWeight: FontWeight.w700,
                    color: Tokens.ink),
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: unit, // :366 stepper-val 的 <small>cm</small>
                  border: InputBorder.none,
                ),
              ),
            ),
            _stepBtn('＋', incKey, incAria,
                () => _bump(ctl, delta, min, max, fixed1: bumpFixed1)),
          ],
        ),
      ],
    );
  }

  /// 44×44 步进按钮（与体重卡 _stepBtn 就地同实现，不过度抽象）
  Widget _stepBtn(String label, Key key, String hint, VoidCallback onTap) {
    return SizedBox(
      key: key,
      width: 44,
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Tokens.line),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusSm)),
        ),
        child: Semantics(
          label: hint,
          child: Text(label,
              style: const TextStyle(
                  fontSize: Tokens.textLg,
                  fontWeight: FontWeight.w700,
                  color: Tokens.primaryDeep)),
        ),
      ),
    );
  }

  /// 分段/芯片统一样式（≙ .segmented button / .chip 的 active 态）
  Widget _seg(String text, bool active, VoidCallback onTap, {Key? key}) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(
                horizontal: Tokens.sp3, vertical: Tokens.sp2),
        decoration: BoxDecoration(
          color: active ? Tokens.primarySoft : Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
          border: Border.all(color: active ? Tokens.primary : Tokens.line),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: Tokens.textSm,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? Tokens.primaryDeep : Tokens.ink2)),
      ),
    );
  }
}
