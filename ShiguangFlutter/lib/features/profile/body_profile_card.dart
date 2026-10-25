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
//   **M7-T7 已脱降级**：actualInfo=actualDeficitProvider（prefs 缓存近 6 天
//   历史+今日实时，≙ state.actualDeficit）。useActual 支（缺口行注记
//   「近N天均值(消耗−摄入)」:1601 / note「缺口为近 N 天实际日均 · 预设 X」
//   :1604）与预设支（「预设缺口 X」:1601 / :1605 两支）同屏互斥。
//   H5 第五行「今日运动」
//   M6-T3 已接线：watch exerciseKcalProvider(todayProvider)，行常驻（值 0 也
//   显，:1589 metab-exercise 恒渲染，注记「今日运动记录累计」:1602）；
//   TDEE/建议摄入值含 ex（:1588/:1591 `tdee+ex`/`suggest+ex`）、公式注记与
//   标题右 note 的 ex>0 支（:1599-1605）逐字对齐。
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
import '../../data/swr_cache.dart' show swrCacheProvider;
import '../../domain/constants.dart' show activity;
import '../../domain/js_compat.dart' show jsFixed1, jsNumText;
import '../../domain/metabolism.dart' show computeMetabolism;
import '../../domain/models.dart' show Body;
import '../common/breathing_capsule.dart' show BreathingCapsule;
import '../common/sheet.dart' show showShiguangSheet;
import '../common/skeleton.dart' show SkeletonBar;
import '../exercise/exercise_controller.dart' show exerciseKcalProvider;
import '../home/home_controller.dart'
    show healthApiProvider, summaryProvider, todayProvider;
import 'goal_edit_sheet.dart' show openGoalEditSheet;
import 'profile_providers.dart' show actualDeficitProvider, profileProvider;

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

/// 目标体重「点击修改」入口（≙ #btn-edit-goal，index.html:199 goal-banner 的
/// 「编辑」小钮 → app.js:1031 openGoalEditSheet。勘正：简报 :1031 一带实读为
/// goal-banner（每日基准目标+目标体重）内 class=edit 文案「编辑」；spec §4.3
/// 裁定 Flutter 落代谢卡目标体重行「点击修改」——本卡即 renderMetab 宿主，
/// 目标体重是代谢计算的输入（:1583），入口随行呈现语义更近）。
@visibleForTesting
const goalEditEntryKey = Key('btn-edit-goal');

/// JS Number→JSON 串形：整数值落 int（168.0 → 168，同 js JSON.stringify）。
num _jsNumOut(num v) =>
    v is double && v == v.truncateToDouble() && v.abs() < 1e15 ? v.toInt() : v;

/// profile.body → Body（简报 Step 2 逐字取法；缺字段回落 Body.fromMap 默认档）
Body _bodyOf(Map<String, dynamic> p) =>
    Body.fromMap(((p['body'] ?? const {}) as Map).cast<String, Object?>());

/// 保存链（≙ body-save :1696-1702 + syncTarget :1706-1718；简报裁定签名：
/// toast 由调用方传页面 _toast/弹层宿主 toast，不做 ref 扩展）。
/// 次序：updateProfile(bodyMap) → suggest≠goal.dailyKcal 才 setGoal →
/// toast；失败仍走 toast「已本地保存：…」；无论成败收尾双 invalidate
/// （profileProvider 重取回真值；summaryProvider family 整族——首页环目标联动）。
/// M7-T5 收口（spec §4.3，M5 旧账）：updateProfile 与 setGoal **拆两 try**——
/// 同 try 时 setGoal 失败会谎报「已本地保存」（profile 实已存成功）；分流后
/// setGoal 失败说「目标同步失败：msg||网络异常」（新支，updateProfile 支
/// 现语义「已本地保存：…」不变）。
/// 身体档案保存中：弹层保存时先关层，卡片标题旁用呼吸胶囊提示在途。
class BodySavingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final bodySavingProvider =
    NotifierProvider<BodySavingNotifier, bool>(BodySavingNotifier.new);

Future<void> saveBodyProfile(WidgetRef ref, Map<String, Object?> bodyMap,
    void Function(String) toast) async {
  final saving = ref.read(bodySavingProvider.notifier)..set(true);
  final api = ref.read(healthApiProvider);
  final profile = ref.read(profileProvider).value ?? const <String, dynamic>{};
  final goal = (profile['goal'] as Map?)?.cast<String, dynamic>() ?? const {};
  final tw = (goal['targetWeight'] as num?)?.toDouble();
  final body = Body.fromMap(bodyMap);
  var profileSaved = false;
  try {
    await api.updateProfile(bodyMap.cast<String, dynamic>()); // :1697
    profileSaved = true;
  } catch (e) {
    final msg = e is ApiException ? e.message : '';
    // :1701 `toast('已本地保存：' + (e.message || '网络异常'))`（空串 falsy 兜底）
    toast('已本地保存：${msg.isEmpty ? '网络异常' : msg}');
  }
  if (profileSaved) {
    try {
      // :1709 computeMetabolism(state.body, tw)——第三参省略 ≙ Flutter 传 null
      final m = computeMetabolism(body, tw, null);
      if (m.suggest != (goal['dailyKcal'] as num?)) {
        // :1715 setGoal({dailyKcal: suggest, targetWeight: tw})；tw 缺省回落当前体重
        await api.setGoal(
            dailyKcal: m.suggest,
            targetWeight: tw ?? body.weightKg.toDouble());
      }
      toast('身体档案已保存'); // :1699 逐字
    } catch (e) {
      final msg = e is ApiException ? e.message : '';
      // 目标同步失败：msg||网络异常（M7-T5 新支——资料已存，不冒充「已本地保存」）
      toast('目标同步失败：${msg.isEmpty ? '网络异常' : msg}');
    }
  }
  ref.invalidate(profileProvider);
  // M9：目标体重/每日基准变更后删 summary 族全部 SWR 键，再整族 invalidate
  // ——防重挂元素以旧 target 播种（首页环目标联动面）。
  ref.read(swrCacheProvider).invalidatePrefix('summary.');
  ref.invalidate(summaryProvider); // family 整族失效（首页环目标联动）
  saving.set(false);
}

/// 身体参数卡（六值 + 代谢明细；点卡开编辑弹层 ≙ #body-card click :1658）
class BodyProfileCard extends ConsumerWidget {
  const BodyProfileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final p = profile.value;
    // M6-T3：今日运动合计（≙ app.js:1586 `state.exerciseKcal || 0`；在途/失败
    // orElse 0 ≙ H5 loadExercises 前缺省与 catch 降级）
    final ex = ref.watch(exerciseKcalProvider(ref.watch(todayProvider)));
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
                  : const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBar(width: 90, height: 14),
                        SizedBox(height: 10),
                        SkeletonBar(height: 12),
                        SizedBox(height: 8),
                        SkeletonBar(width: 180, height: 12),
                      ],
                    ))
              : _cardBody(context, ref, p, ex),
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
    // M9-T8：开层样板收口 showShiguangSheet；泛型 pop 值 Map<String, Object?>
    // 经 helper 原样透传（✕/外触关闭回 null 的判定不变）；标题「身体档案」
    // （index.html:359）原在层内首行，现逐字上移为 helper 标题。
    final bodyMap = await showShiguangSheet<Map<String, Object?>>(
      context,
      title: '身体档案',
      child: _BodyProfileSheet(initial: _bodyOf(p)),
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

  Widget _cardBody(BuildContext context, WidgetRef ref,
      Map<String, dynamic> p, int ex) {
    final b = _bodyOf(p);
    final saving = ref.watch(bodySavingProvider);
    final goal = (p['goal'] as Map?)?.cast<String, dynamic>() ?? const {};
    final tw = (goal['targetWeight'] as num?)?.toDouble();
    // M7-T7：≙ state.actualDeficit（:1584 第三参）。在途/失败/不足 2 天皆
    // null ≙ H5 state.actualDeficit 初值 null → computeMetabolism 预设支。
    final actual = ref.watch(actualDeficitProvider).maybeWhen(
          data: (v) => v,
          orElse: () => null,
        );
    final m = computeMetabolism(b, tw, actual);
    // useActual 闸在 computeMetabolism 内部（avgDeficit>0 && days≥2，
    // :87-88 logic.js），m.useActual==true 时 actual 必非空——:1601/:1604
    // 读 actualDeficit.days 两支各自解构，null 期走预设支。
    final daysText =
        m.useActual ? jsNumText((actual!['days'] as num)) : null;
    final af = (activity[b.activity] ?? activity['light']!).f;
    final bmiShown = (b.bmi ??
            b.weightKg / math.pow(b.heightCm / 100, 2)) // 云端缺 bmi 时补算（防御）
        .toDouble()
        .toStringAsFixed(1); // :1575 Number(bmi).toFixed(1)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('身体档案', // index.html:203 逐字
                style: TextStyle(
                    fontSize: Tokens.textMd,
                    fontWeight: FontWeight.w700,
                    color: Tokens.ink)),
            if (saving) ...[
              const SizedBox(width: Tokens.sp2),
              const BreathingCapsule(
                  minWidth: 28, maxWidth: 58, height: 4, glow: false),
            ],
            const Spacer(),
            const Text('点击编辑 ›', // :203 .more 逐字
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
        const SizedBox(height: Tokens.sp2),
        // 目标体重行（≙ index.html:195-199 goal-banner「目标体重」+ #btn-edit-goal
        // 「编辑」→ app.js:1031 openGoalEditSheet；spec §4.3 裁定 Flutter 入口
        // 文案「点击修改」落本行。值 ≙ renderProfile :1022
        // `${p.goal.targetWeight} <small>kg</small>`，缺 goal 兜 55 ≙ :1429
        // `|| 55` falsy 支。保存链经 profileProvider invalidate 联动本行 +
        // ETA/代谢明细重算（renderMetab 等价，:1458-1459））
        Row(
          children: [
            const Text('目标体重', // index.html:196 逐字
                style: TextStyle(fontSize: Tokens.textXs, color: Tokens.ink2)),
            const SizedBox(width: Tokens.sp2),
            Text.rich(TextSpan(
                style: const TextStyle(
                    fontSize: Tokens.textMd,
                    fontWeight: FontWeight.w700,
                    color: Tokens.ink),
                children: [
                  TextSpan(text: jsNumText(tw ?? 55)),
                  const TextSpan(
                      text: ' kg', // `<small>kg</small>` ≙ 小字单位
                      style: TextStyle(
                          fontSize: Tokens.textXs,
                          fontWeight: FontWeight.w400,
                          color: Tokens.ink3)),
                ])),
            const Spacer(),
            Semantics(
              label: '点击修改', // spec §4.3 入口文案逐字
              button: true,
              container: true,
              child: GestureDetector(
                key: goalEditEntryKey,
                behavior: HitTestBehavior.opaque,
                onTap: () => openGoalEditSheet(context, ref),
                child: const Padding(
                  padding: EdgeInsets.all(Tokens.sp1),
                  child: Text('点击修改 ›',
                      style:
                          TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3)),
                ),
              ),
            ),
          ],
        ),
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
            Text(
                // :1603-1605 note 三支逐字：useActual 支（M7-T7 接入）优先，
                // 否则 ex>0/0 两支（M6-T3 已可真实到达）
                m.useActual
                    ? '缺口为近 $daysText 天实际日均 · 预设 ${jsNumText(m.realDeficit)}'
                    : ex > 0
                        ? '含今日运动 $ex kcal · 基准 ${jsNumText(m.suggest)}'
                        : '基准目标 ${jsNumText(m.suggest)} kcal',
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
            '${jsNumText(m.tdee + ex)} kcal', // :1588 值含 ex（H5 tdee+ex）
            'BMR×系数${jsNumText(af)}${ex > 0 ? '＋今日运动$ex' : ''}'), // :1599 两支逐字
        _metabLine(
            '今日建议摄入', // :219
            '${jsNumText(m.suggest + ex)} kcal', // :1591 值含 ex（与首页环额度同源）
            '消耗${jsNumText(m.tdee)}−缺口${jsNumText(m.realDeficit)}${ex > 0 ? '＋运动$ex' : ''}'), // :1600 两支逐字
        _metabLine(
            '每日缺口', // :220
            '${jsNumText(m.effDeficit)} kcal', // useActual 时 effDeficit=avgDeficit（metabolism.dart）
            m.useActual
                ? '近$daysText天均值(消耗−摄入)' // :1601 useActual 支逐字
                : '预设缺口 ${jsNumText(m.realDeficit)}'), // :1601 非 useActual 支逐字
        _metabLine(
            '今日运动', // index.html:219 DOM 第 5 行（每日缺口之后）
            '${jsNumText(ex)} kcal', // :1589 常驻（值 0 也显「0 kcal」）
            '今日运动记录累计'), // :1602 注记常驻逐字
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
    // M9-T8：标题「身体档案」+ ✕（index.html:359-360）与内层 SafeArea 由
    // showShiguangSheet 承载，本地副本删除；0.9h ConstrainedBox 原样保留
    // （helper 78% 上限更紧，实际生效者为其）；顶部 sp3 归零（其下原有
    // SizedBox(sp3) 承接净距）；viewInsets 包裹与可滚表单保留（表单长目检项）。
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        // 表单长（六组控件+保存）：限高可滚动（R4 关注滚动可用性）
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              Tokens.sp5, 0, Tokens.sp5, Tokens.sp4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
