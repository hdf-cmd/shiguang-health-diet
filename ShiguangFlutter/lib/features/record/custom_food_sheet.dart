// ShiguangFlutter/lib/features/record/custom_food_sheet.dart
// M5 Task 7：自定义食物表单弹层（名称+份量单位+餐次三档+三素+热量+选图，双保存模式）。
// 行为权威源 js/app.js:1170-1286 + index.html:506-558（cf-sheet DOM），逐字口径：
// - 默认值（openCustomFoodSheet :1207-1223）：名称=当时搜索关键词（:1208
//   sheetKeyword，Flutter 侧由调用方以 initialName 传入）；克数/三素/热量清空；
//   cfKcalManual 复位；单位默认克（:1216）；餐次档默认随入参餐次
//   （:1218：breakfast→早餐 / snack→零食 / 其余(午·晚)→正餐）。
// - 宏量自动热量（cfAutoKcal :1195-1202）：三素任一有值且未手改热量 →
//   kcal = Math.round(4p+4c+9f)（:1201）；三素全空不动热量（:1200，允许只按
//   包装标签填热量）；手改热量落下 cfKcalManual 闸（:1172/1283），此后宏量
//   再变不覆盖。
// - 保存闸（saveCustomFood :1229-1239）：名称 trim 空 →「请填写食物名称」；
//   kcal falsy/<=0 →「请填热量，或先填三大营养素自动算」；portion =
//   grams ? `${grams}${unit}` : '1 份'（:1236）；meals = CF_MEAL_MAP 三档
//   （:1176：早→[breakfast] 正餐→[lunch,dinner] 零食→[snack]）。
// - 提交体（:1241/:1244 逐键）：入库 {name,kcal,grams,unit,meals,protein,carb,
//   fat,portion,image}；记入 {date,meal(入参餐次),name,portion,kcal,emoji:'🍽️',
//   image,protein,carb,fat}。
// - 成功序（简报裁定，close 时点 ≙ H5 :1242）：addCustomFood → pop → onSaved
//   （≙ :1251 fillSheetResults 重查）→（记入则）addFoodRecord → toast
//   「已存入食物库，搜索可用」(:1250) / 「已记入${MEAL_NAMES[餐次]} · ${名}」
//   (:1248)；任一失败 catch →「保存失败：${msg||网络异常}」(:1254)。记录刷新走
//   record_controller.addRecord 现成链（内部 invalidate 当日 records+summary，
//   ≙ :1246-1247 refreshToday+loadRecordPage）。记入日期用调用方传入的
//   [date]（M5-T8 结转 A①：≙ H5 在途常读全局 today 的当日语义，Flutter 侧
//   消「弹层开着跨午夜、记入跑明天」双轨——search_sheet 传 widget.date）。
// - 选图（cf-img-pick/change :1257-1272，经 T3 pickCompressedImageDataUrl）：
//   取消静默（:1260 !file return）；压缩后超限→「图片仍过大，请换一张」
//   （:1266 逐字）；读取/编码失败→「图片处理失败」（:1270 逐字）。预览
//   renderCfPreview :1203-1206：有图画图、空画 🍽️。
//   H5 单按钮「添加图片」→ Flutter 简报裁定「拍照/从相册选择」双钮 + 清除钮
//   （原生来源区分，R4 差异登记）；
// M7-T8 终裁登记（有意背离，列 M7 终审呈报项）：H5 fromLib 入口（app.js:1207
// 形参，:1220 主钮文案改「存入食物库」、:1221 藏次钮）与其 handler 行为不一致
// ——点击仍走 :1276 `saveCustomFood(true)` 照记一餐，**文案撒谎**。本端从行为
// 不从文案：维持双钮完整形态（钮面文案与真实行为一致），不实现 fromLib 单钮；
// 管理层入口见 food_lib_sheet.dart（T4 已立，旧注「Flutter 无管理页」已过时，
// 本批随终裁一并勘正）。选择器不进 widget 测试：CustomFoodImagePicker 注入面，
//   做法同 T5 AvatarPicker。
// 文案与简报差异以 H5 源为准：次按钮「仅存入食物库，不记录」（index.html:557
// 逐字，简报省略「，不记录」）；自动热量 p5/c40/f6=234（:1201 公式；简报②⑤
// 写 250 为算术笔误，报告登记）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../data/swr_cache.dart' show swrCacheProvider;
import '../../domain/constants.dart';
import '../../domain/dates.dart';
import '../common/food_thumb.dart';
import '../common/image_pick.dart';
import 'record_controller.dart';

/// 选图注入面（≙ T5 AvatarPicker 做法）：入参来源，返回压缩 dataURL/失败态。
typedef CustomFoodImagePicker = Future<PickedImageData> Function(
    ImageSource source);

/// 生产默认：走 T3 原生重编码管道
Future<PickedImageData> _defaultPickImage(ImageSource source) =>
    pickCompressedImageDataUrl(source);

/// 表单三档类别 → 内置 meals 语义（CF_MEAL_MAP js/app.js:1176 逐字）
const cfMealMap = <String, List<String>>{
  'breakfast': ['breakfast'],
  'lunch': ['lunch', 'dinner'],
  'snack': ['snack'],
};

/// Number(v)||0 的 Dart 等价：非法/空 → 0；整数值归一为 int，使
/// `${grams}${unit}` 与 JSON 序列化文本同 JS（'100g' 而非 '100.0g'）。
num jsFormNum(String raw) {
  final v = num.tryParse(raw.trim());
  if (v == null) return 0; // Number('')=0 / Number('abc')=NaN→||0 同落 0
  if (v is double && v == v.roundToDouble() && v.abs() < 1e15) return v.toInt();
  return v;
}

@visibleForTesting
const cfNameKey = Key('cf-name'); // index.html:514 id 同名

@visibleForTesting
const cfGramsKey = Key('cf-grams'); // :520

@visibleForTesting
const cfKcalKey = Key('cf-kcal'); // :545

@visibleForTesting
const cfProteinKey = Key('cf-protein'); // :538

@visibleForTesting
const cfCarbKey = Key('cf-carb'); // :539

@visibleForTesting
const cfFatKey = Key('cf-fat'); // :540

@visibleForTesting
const cfSaveAddKey = Key('cf-save-add'); // :556

@visibleForTesting
const cfSaveOnlyKey = Key('cf-save-only'); // :557

@visibleForTesting
const cfImgCameraKey = Key('cf-img-camera'); // 简报双钮（H5 单钮 :551 的拆分）

@visibleForTesting
const cfImgGalleryKey = Key('cf-img-gallery');

@visibleForTesting
const cfImgClearKey = Key('cf-img-clear');

@visibleForTesting
Key cfUnitKey(String unit) => Key('cf-unit-$unit'); // :522-523 data-unit

@visibleForTesting
Key cfMealKey(String kind) => Key('cf-meal-$kind'); // :530-532 data-meal

/// 打开自定义食物表单（≙ openCustomFoodSheet，:1207）。
/// [date] 记入目标日期（M5-T8 结转 A①：调用方传当日/弹层日期，≙ H5 在途常读
/// 的全局 today）；[meal] 记入目标餐次（breakfast/lunch/dinner/snack）；
/// [initialName] = 当时搜索关键词（:1208 sheetKeyword 语义）；[onSaved] 由
/// search_sheet 传「以当前关键词重查」。[pickImage] 仅测试注入面，生产缺省走 T3 管道。
Future<void> openCustomFoodSheet(
  BuildContext context, {
  required String date,
  required String meal,
  String? initialName,
  required void Function() onSaved,
  CustomFoodImagePicker pickImage = _defaultPickImage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // 键盘弹出/表单滚到底（目检项）
    backgroundColor: Tokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(Tokens.radiusSheet)),
    ),
    builder: (_) => _CustomFoodSheet(
      date: date,
      meal: meal,
      initialName: initialName,
      onSaved: onSaved,
      pickImage: pickImage,
    ),
  );
}

/// 分段档按钮（克|毫升、早餐|正餐|零食）。selected 公开供测试断言档位归属。
class CfSegButton extends StatelessWidget {
  const CfSegButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: Tokens.sp4, vertical: Tokens.sp2),
        decoration: BoxDecoration(
          color: selected ? Tokens.surface : Tokens.surface2, // ≙ .active
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
          boxShadow: selected ? const [Tokens.shadowSegmented] : const [],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: Tokens.textSm,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Tokens.primaryDeep : Tokens.ink2,
          ),
        ),
      ),
    );
  }
}

class _CustomFoodSheet extends ConsumerStatefulWidget {
  const _CustomFoodSheet({
    required this.date,
    required this.meal,
    required this.initialName,
    required this.onSaved,
    required this.pickImage,
  });

  final String date;
  final String meal;
  final String? initialName;
  final void Function() onSaved;
  final CustomFoodImagePicker pickImage;

  @override
  ConsumerState<_CustomFoodSheet> createState() => _CustomFoodSheetState();
}

class _CustomFoodSheetState extends ConsumerState<_CustomFoodSheet> {
  // :1208 名称=搜索词；其余框初始空（:1209-1213）
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName ?? '');
  final TextEditingController _grams = TextEditingController();
  final TextEditingController _kcal = TextEditingController();
  final TextEditingController _protein = TextEditingController();
  final TextEditingController _carb = TextEditingController();
  final TextEditingController _fat = TextEditingController();

  /// 挂层即冻结当前本地时刻（M5-T8 结转 A①）：widget.date 为空时兜底用
  /// 「打开弹层那一刻」的当日，而非保存瞬间的 todayIso()——挂层跨午夜
  /// 不再把记入推到明天。search_sheet 正常会传 widget.date。
  late final DateTime _now = DateTime.now();

  bool _kcalManual = false; // :1172 手改热量闸
  bool _addedToLib = false; // 入库已成功（记录失败重试时不重复入库，见 _save）
  bool _busy = false; // 保存链在途（重入禁用两钮）
  bool _picking = false; // 选图在途

  String _unit = 'g'; // :1173 默认克

  /// :1174/1218 三档类别，入参餐次映射：breakfast→早餐 / snack→零食 / 其余→正餐
  late String _mealKind = switch (widget.meal) {
    'breakfast' => 'breakfast',
    'snack' => 'snack',
    _ => 'lunch',
  };

  String _imageData = ''; // :1171 压缩后 dataURL，空串=无图

  @override
  void dispose() {
    _name.dispose();
    _grams.dispose();
    _kcal.dispose();
    _protein.dispose();
    _carb.dispose();
    _fat.dispose();
    super.dispose();
  }

  static String _reason(Object e) {
    final m = e is ApiException ? e.message : null;
    return (m == null || m.isEmpty) ? '网络异常' : m; // :1254 e.message||'网络异常'
  }

  void _toast(ScaffoldMessengerState m, String msg) {
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  /// cfAutoKcal :1195-1202：手改闸下跳过；三素全空不动热量；否则
  /// round(4p+4c+9f) 写回热量框（程序化赋值不触 _kcal.onChanged，闸不误伤）
  void _autoKcal() {
    if (_kcalManual) return;
    final p = jsFormNum(_protein.text);
    final c = jsFormNum(_carb.text);
    final f = jsFormNum(_fat.text);
    if (p == 0 && c == 0 && f == 0) return; // :1200
    _kcal.text = (p * 4 + c * 4 + f * 9).round().toString(); // :1201 Math.round
  }

  /// 选图（≙ #cf-img-pick click → #cf-img-input change，:1257-1272）
  Future<void> _pick(ImageSource source) async {
    if (_picking) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _picking = true);
    try {
      final r = await widget.pickImage(source);
      if (!mounted) return;
      if (r.failure == null && r.dataUrl == null) return; // :1260 取消静默
      if (r.failure == ImagePickFailure.tooLargeEncoded) {
        _toast(messenger, '图片仍过大，请换一张'); // :1266 逐字
        return;
      }
      if (r.failure == ImagePickFailure.readFailed) {
        _toast(messenger, '图片处理失败'); // :1270 逐字
        return;
      }
      setState(() => _imageData = r.dataUrl!); // renderCfPreview :1205 ≙ FoodThumb
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// 保存（≙ saveCustomFood(andAdd)，:1229-1256）
  Future<void> _save(bool andAdd, ScaffoldMessengerState messenger) async {
    if (_busy) return;
    final name = _name.text.trim(); // :1230
    final kcal = jsFormNum(_kcal.text); // :1231
    final grams = jsFormNum(_grams.text); // :1232
    final protein = jsFormNum(_protein.text);
    final carb = jsFormNum(_carb.text);
    final fat = jsFormNum(_fat.text);
    if (name.isEmpty) {
      _toast(messenger, '请填写食物名称'); // :1238 逐字
      return;
    }
    if (kcal <= 0) {
      // :1239 逐字（!kcal || kcal<=0 合并：falsy 与负数同闸）
      _toast(messenger, '请填热量，或先填三大营养素自动算');
      return;
    }
    final portion = grams != 0 ? '$grams$_unit' : '1 份'; // :1236
    final meals = cfMealMap[_mealKind] ?? const <String>[]; // :1237
    final controller = ref.read(recordControllerProvider);
    setState(() => _busy = true);
    try {
      if (!_addedToLib) {
        // :1241 十字键逐字；T2 addCustomFood（POST /foods/custom）
        await ref.read(healthApiProvider).addCustomFood(<String, dynamic>{
          'name': name,
          'kcal': kcal,
          'grams': grams,
          'unit': _unit,
          'meals': meals,
          'protein': protein,
          'carb': carb,
          'fat': fat,
          'portion': portion,
          'image': _imageData,
        });
        _addedToLib = true;
        // M9-T4 写路径「先删键再刷新」：食物库会话缓存键随入库失效
        // （口径同 food_lib_sheet 归类/删除链、weight_log_card :145 定式；
        // 键名两处约定，不交叉 import 防环）。
        ref.read(swrCacheProvider).invalidate('foods.custom');
      }
      if (mounted) Navigator.of(context).pop(); // :1242 入库成功即关（先于记入，
      // 使「记入失败」不再提供重复入库的重入口——与 H5 close-then-add 同形）
      // onSaved ≙ H5 :1251 fillSheetResults 重查（差异登记，M5 终审 F3：
      // H5 仅「仅入库」分支重查，「保存并记入」分支 closeSheet 回当日视图
      // 不重查；Flutter 两分支统一回调＝良性增强——记入后列表同步可见）。
      widget.onSaved();
      if (andAdd) {
        // :1244 记录 body 十字键；addRecord 内部 invalidate 当日
        // records+summary（≙ :1246-1247 refreshToday+loadRecordPage）+ 常吃续算。
        // 记入日=widget.date（M5-T8 结转 A①；空值兜底挂层时刻 _now，
        // 不再取保存瞬间的 todayIso——消跨午夜「记入跑明天」双轨）
        final recordDate =
            widget.date.isNotEmpty ? widget.date : localIso(_now);
        await controller.addRecord(
          recordDate,
          <String, dynamic>{
            'date': recordDate,
            'meal': widget.meal, // 入参餐次（早/午/晚/零食），非三档类别
            'name': name,
            'portion': portion,
            'kcal': kcal,
            'emoji': '🍽️', // :1244 逐字
            'image': _imageData,
            'protein': protein,
            'carb': carb,
            'fat': fat,
          },
          pendingKey: 'custom:$name',
        );
        _toast(messenger, '已记入${mealNames[widget.meal] ?? ''} · $name'); // :1248 逐字
      } else {
        _toast(messenger, '已存入食物库，搜索可用'); // :1250 逐字
      }
    } catch (e) {
      _toast(messenger, '保存失败：${_reason(e)}'); // :1254 逐字
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _label = TextStyle(
      fontSize: Tokens.textSm, fontWeight: FontWeight.w700, color: Tokens.ink);
  static const _sub = TextStyle(fontSize: Tokens.textXs, color: Tokens.ink3);

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        counterText: '',
      );

  @override
  Widget build(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    return Padding(
      // 键盘上滚（目检项：两钮不遮）
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        // 不设百分比 maxHeight：BottomSheet 自身把 isScrollControlled 弹层
        // 限到屏高，SingleChildScrollView  viewport=弹层实高即可滚到两钮
        //（MediaQuery 路由内值≠测试 setSurfaceSize，勿依赖其做高度预算）
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              Tokens.sp5, Tokens.sp3, Tokens.sp5, Tokens.sp4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                // 标题「自定义食物」+ ✕（index.html:509-511）
                Row(
                  children: [
                    const Text('自定义食物', style: TextStyle(
                        fontSize: Tokens.textLg,
                        fontWeight: FontWeight.w800,
                        color: Tokens.ink)),
                    const Spacer(),
                    Semantics(
                      label: '关闭', // :511 aria-label 逐字
                      button: true,
                      child: GestureDetector(
                        key: const Key('sheet-close'),
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
                // 食物名称（:513-515，maxlength=30，占位逐字）
                const Text('食物名称', style: _label),
                const SizedBox(height: Tokens.sp1),
                TextField(
                  controller: _name,
                  key: cfNameKey,
                  maxLength: 30, // :514
                  decoration: _field('如：妈妈牌红烧肉'), // :514 逐字
                ),
                const SizedBox(height: Tokens.sp3),
                // 一份份量 + 克|毫升（:517-526）
                const Text('一份份量', style: _label), // :518 逐字
                const Text('填了才能按份量加', style: _sub), // :518 逐字
                const SizedBox(height: Tokens.sp1),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _grams,
                        key: cfGramsKey,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_numberFieldFormatter],
                        decoration: _field('如：200'), // :520 逐字
                      ),
                    ),
                    const SizedBox(width: Tokens.sp2),
                    CfSegButton(
                      key: cfUnitKey('g'),
                      label: '克', // :522 逐字
                      selected: _unit == 'g',
                      onTap: () => setState(() => _unit = 'g'), // setCfUnit :1187
                    ),
                    const SizedBox(width: Tokens.sp2),
                    CfSegButton(
                      key: cfUnitKey('ml'),
                      label: '毫升', // :523 逐字
                      selected: _unit == 'ml',
                      onTap: () => setState(() => _unit = 'ml'),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.sp3),
                // 适合哪一餐 三档（:527-534；setCfMeal :1191，
                // CF_MEAL_MAP 合法性闸 :1192 恒真——三钮即全集）
                const Text('适合哪一餐', style: _label), // :528 逐字
                const Text('决定搜索时出现在哪些餐次', style: _sub), // :528 逐字
                const SizedBox(height: Tokens.sp1),
                Row(
                  children: [
                    for (final kind in const ['breakfast', 'lunch', 'snack'])
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              right: kind == 'snack' ? 0 : Tokens.sp2),
                          child: CfSegButton(
                            key: cfMealKey(kind),
                            label: switch (kind) {
                              'breakfast' => '早餐', // :530 逐字
                              'lunch' => '正餐', // :531 逐字
                              _ => '零食', // :532 逐字
                            },
                            selected: _mealKind == kind,
                            onTap: () =>
                                setState(() => _mealKind = kind), // :1191-1194
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Tokens.sp3),
                // 三大营养素（:535-542；oninput→cfAutoKcal :1279-1282）
                const Text('三大营养素', style: _label), // :536 逐字
                const Text('这一份的含量（克）', style: _sub), // :536 逐字
                const SizedBox(height: Tokens.sp1),
                Row(
                  children: [
                    _macroField('蛋白质', _protein, cfProteinKey), // :538
                    const SizedBox(width: Tokens.sp2),
                    _macroField('碳水', _carb, cfCarbKey), // :539
                    const SizedBox(width: Tokens.sp2),
                    _macroField('脂肪', _fat, cfFatKey), // :540
                  ],
                ),
                const SizedBox(height: Tokens.sp3),
                // 热量 kcal（:543-546；input→manual 闸 :1283）
                const Text('热量 kcal', style: _label), // :544 逐字
                const Text('按营养素自动算，可手改', style: _sub), // :544 逐字
                const SizedBox(height: Tokens.sp1),
                TextField(
                  controller: _kcal,
                  key: cfKcalKey,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => _kcalManual = true, // :1283
                  decoration: _field('如：350'), // :545 逐字
                ),
                const SizedBox(height: Tokens.sp3),
                // 图片（:547-553 + 简报双钮/清除）
                const Text('图片'), // :548 逐字
                const Text('可选', style: _sub), // :548 逐字
                const SizedBox(height: Tokens.sp1),
                Row(
                  children: [
                    // 预览：有图画图、空画 🍽️（renderCfPreview :1203-1206）
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: Center(
                        child: FoodThumb(
                          source: _imageData,
                          emoji: '🍽️',
                          size: 64,
                        ),
                      ),
                    ),
                    const SizedBox(width: Tokens.sp3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton( // 主题债：FilledButton 进 Row
                            key: cfImgCameraKey, // 非 flex 位不渲染 → Expanded
                            onPressed: _picking || _busy
                                ? null
                                : () => _pick(ImageSource.camera),
                            child: const Text('拍照'), // 简报逐字（R4：H5 单钮拆分）
                          ),
                          const SizedBox(height: Tokens.sp1),
                          OutlinedButton(
                            key: cfImgGalleryKey,
                            onPressed: _picking || _busy
                                ? null
                                : () => _pick(ImageSource.gallery),
                            child: const Text('从相册选择'), // 简报逐字
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Tokens.sp2),
                    IconButton(
                      key: cfImgClearKey,
                      onPressed: _imageData.isEmpty || _picking || _busy
                          ? null
                          : () => setState(() => _imageData = ''), // 简报清除钮
                      icon: const Icon(Icons.delete_outline,
                          color: Tokens.ink3),
                      tooltip: '清除',
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.sp4),
                // 双保存（:555-557；主按钮标题随入参餐次 :1220。
                // fromLib 单钮形态 T8 终裁不做——H5 该形态文案撒谎（:1220 vs
                // :1276 行为），本端从行为不从文案，见文件头「有意背离」登记）
                FilledButton(
                  key: cfSaveAddKey,
                  onPressed: _busy
                      ? null
                      : () => _save(
                          true,
                          messenger), // :1276 saveCustomFood(true)
                  child: Text('保存并记入${mealNames[widget.meal] ?? '本餐'}'), // :1220
                ),
                const SizedBox(height: Tokens.sp2),
                OutlinedButton( // :557 btn-quiet（R4：Outlined 而非 tonal——
                  key: cfSaveOnlyKey, // tonal 被主题 filledButtonTheme 刷成深绿，
                  onPressed: _busy // 与主钮无层级差，目检抓得）
                      ? null
                      : () => _save(
                          false,
                          messenger), // :1277 saveCustomFood(false)
                  child: const Text('仅存入食物库，不记录'), // :557 逐字
                ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _macroField(String label, TextEditingController ctl, Key key) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _sub), // 蛋白质/碳水/脂肪 :538-540 逐字
          TextField(
            controller: ctl,
            key: key,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _autoKcal(), // :1279-1282
            decoration: _field('0'), // :538-540 placeholder 逐字
          ),
        ],
      ),
    );
  }
}

/// 数字框输入收口：只允许数字+小数点（min/max 语义由保存闸兜底——H5 JS 侧
/// 同样不校验 HTML 属性 min/max，行为对齐源）。
/// M5-T8 结转 A②（探针实证后换，test/custom_food_sheet_test.dart
/// 「数字框字符类格式器」用例）：原 `^[0-9]*\.?[0-9]*$` 整串锚定在
/// FilteringTextInputFormatter.allow 的「逐段提取匹配」语义下失效——
/// '12.3.4'/'1e9'/'-5'/'.5.' 整串不匹配一律被**整体清空**（丢已输合法
/// 内容；M5 终审 F1 勘误：旧表述称 '.5.' 被剪成 '5.' 放行非法多小数点，
/// 复跑旧正则证实 allMatches 无匹配→join 为空串，'.5.' 亦整体清空）。
/// 字符类式逐字符过滤：
/// 合法字符保留、非法字符剔除。多小数点（'1.2.3'）不再被格式器拦下，
/// 由 jsFormNum 解析失败归 0 + 保存闸（热量<=0 拒）兜底，与 H5
/// `Number(v)||0` 语义同形（H5 的 type=number 非法值同样到不了业务层）。
final _numberFieldFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));
