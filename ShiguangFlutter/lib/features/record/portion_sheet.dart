// ShiguangFlutter/lib/features/record/portion_sheet.dart
// per100 食物「按克加」份量弹层（M2 Task 9）。
// 行为权威源 js/app.js:714-781：标题「${f.name} · 自定义份量」（721）、
// 初始克数 = f.baseG || 100（722）、单位 cfUnitOf（720，js/app.js:1185 仅 ml/g）、
// 实时预览「${g}g ≈ ${kcal} kcal · 蛋白 p / 碳水 c / 脂肪 f」（733-738，
// 换算=domain/portion.dart portionMacros，镜像 js/logic.js:125-134）、
// 确认按钮「确认添加」（index.html:502）、记入 body（765-768，portion=`${g}${unit}`）、
// 成功 toast「已添加 X Ng」（764）。
// 与 H5 差异（交互层 R4 自主）：M2 简报定滑杆、老大 09-27 真机反馈改回
// ± 步进钮（一档 5）——步进 5、下限取 5 的整步格、上限沿用 H5 bumpBodyVal
// 的 2000 封顶（js/app.js:739-741）；记入 body/预览换算数据语义零变。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/models.dart' show Per100;
import '../../domain/portion.dart' show portionMacros;
import '../common/sheet.dart' show showShiguangSheet;
import 'record_controller.dart';

/// 滑杆取值域与步进（简报：1-maxG 步进 5；下限取 5 保证整步格，上限沿用 H5 2000）
const double _kMinG = 5;
const double _kMaxG = 2000;
const double _kStepG = 5;

double _snap(num grams) {
  final v = grams.clamp(_kMinG, _kMaxG).toDouble();
  return (_kMinG + ((v - _kMinG) / _kStepG).roundToDouble() * _kStepG)
      .clamp(_kMinG, _kMaxG)
      .toDouble();
}

Future<void> showPortionSheet(
  BuildContext context, {
  required Map<String, dynamic> food,
  required String date,
  required String meal,
}) {
  // M9-T8：开层样板收口 showShiguangSheet；标题「X · 自定义份量」
  // （js/app.js:721）原在层内首行，现逐字上移为 helper 标题。
  final name = '${food['name'] ?? ''}';
  return showShiguangSheet<void>(
    context,
    title: '$name · 自定义份量',
    child: PortionSheet(food: food, date: date, meal: meal),
  );
}

class PortionSheet extends ConsumerStatefulWidget {
  const PortionSheet({
    super.key,
    required this.food,
    required this.date,
    required this.meal,
  });

  final Map<String, dynamic> food;
  final String date;
  final String meal;

  @override
  ConsumerState<PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends ConsumerState<PortionSheet> {
  /// 当前克数/毫升数（H5 #portion-g-val），初始 = baseG || 100（js/app.js:722）
  late double _grams =
      _snap((widget.food['baseG'] as num?)?.toDouble() ?? 100);

  /// cfUnitOf（js/app.js:1185）：unit==='ml' 按毫升，否则按克
  String get _unit => widget.food['unit'] == 'ml' ? 'ml' : 'g';

  Per100 get _per100 {
    final p = widget.food['per100'];
    return p is Map
        ? Per100.fromMap(Map<String, Object?>.from(p))
        : const Per100(kcal: 0, protein: 0, carb: 0, fat: 0);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 在途键与搜索弹层同键（食物 id，缺 id 退化 name）→ 同一食物只有一个
  /// 在途写请求，H5「点了就 disabled」的语义（js/app.js:677/693）。
  String get _pendingKey =>
      '${widget.food['id'] ?? widget.food['name'] ?? ''}';

  bool get _pending =>
      ref.read(recordControllerProvider).isInFlight(_pendingKey);

  /// ± 步进一档 5（老大 09-27 真机反馈：滑杆改加减）；边界/整步格沿用 _snap
  void _bump(double delta) => setState(() => _grams = _snap(_grams + delta));

  /// 确认记入：body 对齐 js/app.js:765-768（portion=`${g}${unit}`，宏量按克换算）
  Future<void> _save() async {    final controller = ref.read(recordControllerProvider);
    if (controller.isInFlight(_pendingKey)) return; // 连点丢弃（H5 btn.disabled）
    final g = _grams.round();
    if (g < 10) {
      // H5 js/app.js:749 兜底（滑杆下限 5 时仅防手动异常）
      _toast('请输入${_unit == 'ml' ? '毫升数' : '克数'}');
      return;
    }
    final r = portionMacros(_per100, g);
    final body = <String, dynamic>{
      'date': widget.date,
      'meal': widget.meal,
      'name': widget.food['name'] ?? '',
      'portion': '$g$_unit',
      'kcal': r.kcal,
      'emoji': widget.food['emoji'] ?? '',
      'protein': r.protein,
      'carb': r.carb,
      'fat': r.fat,
      'image': widget.food['image'] ?? '',
    };
    // pop 后本 State 即卸载，先捕获 messenger（SnackBar 在根 ScaffoldMessenger 层渲染）
    final messenger = ScaffoldMessenger.of(context);
    final pending =
        controller.addRecord(widget.date, body, pendingKey: _pendingKey);
    // addRecord 同步登记在途后立即重绘 → pending 期按钮禁用 +「请稍候…」（js:677/1902）
    if (mounted) setState(() {});
    try {
      if (await pending) {
        if (!mounted) return;
        Navigator.of(context).pop(); // 份量弹层收起，回到搜索弹层可继续（H5 763）
        messenger.showSnackBar(SnackBar(
            content: Text(
                '已添加 ${widget.food['name'] ?? ''} $g$_unit · 可继续添加')));
      }
    } on ApiException catch (e) {
      _toast('添加失败：${e.message}');
    } catch (_) {
      _toast('添加失败：网络异常');
    } finally {
      if (mounted) setState(() {}); // 失败留在弹层时恢复按钮（H5 693）
    }
  }

  /// ± 步进钮（与体重卡 _stepBtn 同款观感：44×44 描边圆角，primaryDeep 字）
  Widget _stepBtn(String label, VoidCallback onTap, String hint) {
    return Semantics(
      label: hint,
      button: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: OutlinedButton(
          onPressed: _pending ? null : onTap,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Tokens.line),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Tokens.radiusSm)),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: Tokens.textLg,
                  fontWeight: FontWeight.w700,
                  color: Tokens.primaryDeep)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = portionMacros(_per100, _grams.round());
    // M9-T8：标题「X · 自定义份量」（js/app.js:721）与 ✕（原
    // ValueKey('portion-close') IconButton，tooltip「关闭」）由
    // showShiguangSheet 标题行承载，本地副本删除；内层 SafeArea 与
    // helper 重复去内层留 helper 的。滑杆/预览/确认钮业务 widget 不改。
    return Padding(
      padding: const EdgeInsets.all(Tokens.sp4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _stepBtn('−', () => _bump(-_kStepG), '减少 5$_unit'), // 档位键同权重卡定式
              Expanded(
                child: Center(
                  child: Text(
                    '${_grams.round()}$_unit',
                    style: const TextStyle(
                        fontSize: Tokens.textXl,
                        fontWeight: FontWeight.w800,
                        color: Tokens.primaryDeep),
                  ),
                ),
              ),
              _stepBtn('＋', () => _bump(_kStepG), '增加 5$_unit'),
            ],
          ),
          // 换算提示（js/app.js:724 语义；滑杆改 ± 系老大 09-27 真机反馈，
          // 文案随之从「拖动滑杆」改「点 −/＋」——交互层 R4 自主，数据语义零变）
          const SizedBox(height: Tokens.sp1),
          Text(
            '点 −/＋ 调整$_unit数（一档 ${_kStepG.round()}$_unit），营养按每 100$_unit 换算',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3),
          ),
          const SizedBox(height: Tokens.sp3),
          // 实时宏量预览（js/app.js:737）
          Container(
            key: const ValueKey('portion-preview'),
            padding: const EdgeInsets.all(Tokens.sp3),
            decoration: BoxDecoration(
              color: Tokens.primarySoft,
              borderRadius: BorderRadius.circular(Tokens.radiusMd),
            ),
            child: Text(
              '${_grams.round()}$_unit ≈ ${r.kcal.round()} kcal · 蛋白 ${r.protein}g / 碳水 ${r.carb}g / 脂肪 ${r.fat}g',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: Tokens.textMd,
                  fontWeight: FontWeight.w700,
                  color: Tokens.primaryDeep),
            ),
          ),
          const SizedBox(height: Tokens.sp4),
          FilledButton(
            // pending 期禁用 +「请稍候…」（H5 js/app.js:677/693 disabled 语义，
            // 文案同 js/app.js:1902 提交态），完成后随 setState 恢复
            onPressed: _pending ? null : _save,
            child: Text(_pending ? '请稍候…' : '确认添加'),
          ),
        ],
      ),
    );
  }
}
