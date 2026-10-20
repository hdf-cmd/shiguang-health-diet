// ShiguangFlutter/lib/features/record/food_scan_sheet.dart
// M13-T6：拍照识菜的确认表单 + 保存链。
// 行为权威源 spec §3.2-3.4（docs/superpowers/specs/2026-10-20-flutter-m13-ai-food-scan-design.md）：
// - 顶部入库照片缩略图（默认=识别图）：scan-pick-photo 换图（走选图注入面，
//   换图不重新识别）、scan-remove-photo 清空（入库/记账 image 落空串，行内回退 emoji）；
// - 菜名预填模型建议（可改，必填 ≤30 字）；克数默认 200g（1–2000）；
//   每 100g 四项可改；汇总随克数/数值即时重算（scanPortionTotals，M13-T6 起与
//   portionMacros 同走 jsRound/jsFixed1）；
// - confidence=low → 黄字「识别把握不大，请核对菜名与数值」；
// - 保存链：upsert（按份营养 + 入库照片）→ 失败停留在表单并显示「保存失败：…」
//   （不记账）；skipped="builtin" → 不入库、不失效缓存，但照常记账 + toast
//   「内置库已有「X」，本条未重复入库」；成功入库 → 失效 foods.custom 与搜索
//   快照（invalidateFoodLibrary）；recordMeal=true 再走 addRecord（M11 乐观记账，
//   emoji 取 upsert 回包），记账失败 toast「已入库，本餐记入失败：…」仍关层。
// 入口差异：recordMeal=false（食物库入口）只入库不记账。
// toast 走层内 OverlayEntry（SheetToast，food_lib_sheet._toast 同模式）。与既有
// 弹层不同，本层**保存成功/内置同名提示后会立即 pop**；H5 的 #toast 是全局
// 元素，关层不打断（js/app.js:35），故 dispose 不硬摘在播的 toast——由
// onDone（2400ms 动画结束）自删，否则这两条提示会被 pop 动画吞掉。
// 分层：openFoodScanFlow（M13-T7）——选来源（SimpleDialog「拍照/从相册选」，
// 取消静默）→ 选图注入面（scanImagePickProvider，512px/q75）→ 不可关闭的
// 「识别中…」对话框 → scanFood；失败关对话框并弹「识别失败：{msg}」
// （「手动填写」落 openCustomFoodSheet /「取消」静默）；成功关对话框后**经
// showShiguangSheet 开本表单**（toast 依赖根 Navigator Overlay，T6 已验证
// 该宿主形态，不得改为路由根 body）。两个入口（记一笔搜索框 📷 / 食物库
// 「📷 拍照添加」）共用本函数：前者 recordMeal=true（date/meal 用弹层入参），
// 后者 recordMeal=false（date=plateDateProvider、meal='lunch'）。
// M14-T5：识菜前读用户自带厂商配置（设备级密存），随 scanFood 发出；只有
// isUsable（开关开 + id/model/key 齐全）才真正带键（HealthApi 内判定）。
// 存储不可用/未注入按「未配置」回退内置通道——Key 配置是可选增强，
// 不能把存储故障升级成识菜失败。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../../app/theme.dart';
import '../../data/ai_provider_store.dart'
    show AiProviderConfig, aiProviderStoreProvider;
import '../../data/api_client.dart' show ApiException;
import '../../data/swr_cache.dart' show swrCacheProvider;
import '../../domain/constants.dart' show mealNames;
import '../../domain/js_compat.dart' show jsNumText, jsNumber, jsOr;
import '../common/food_thumb.dart';
import '../common/image_pick.dart';
import '../common/sheet.dart' show showShiguangSheet;
import '../common/sheet_toast.dart';
import 'custom_food_sheet.dart' show openCustomFoodSheet;
import 'food_scan_math.dart';
import 'record_controller.dart'
    show healthApiProvider, invalidateFoodLibrary, recordControllerProvider;

/* ---------- Key（简报逐字；widget 测试直接按 Key 定位） ---------- */

@visibleForTesting
const scanNameKey = Key('scan-name');

@visibleForTesting
const scanGramsKey = Key('scan-grams');

@visibleForTesting
const scanKcalKey = Key('scan-kcal');

@visibleForTesting
const scanProteinKey = Key('scan-protein');

@visibleForTesting
const scanCarbKey = Key('scan-carb');

@visibleForTesting
const scanFatKey = Key('scan-fat');

@visibleForTesting
const scanTotalKey = Key('scan-total');

@visibleForTesting
const scanSaveKey = Key('scan-save');

@visibleForTesting
const scanPickPhotoKey = Key('scan-pick-photo');

@visibleForTesting
const scanRemovePhotoKey = Key('scan-remove-photo');

/// 选图注入面（T7 识图与表单换图共用）：入参来源，返回压缩 dataURL/失败态。
typedef ScanImagePick = Future<PickedImageData> Function(ImageSource source);

/// 生产默认：走 T4 扫码参数（512px/q75）——识别图需要足够清晰；换入库照片同
/// 走本管道（同受 maxChars 字符上限约束）。见 [scanImagePickProvider]。

/// 压缩管道注入面（仅测试用）：让用例断言扫码链实际传给压缩管道的
/// maxDim/quality，而不是只断言常量值——常量改了没接线时测试必须能红。
final imageCompressorProvider =
    Provider<ImageCompressor>((ref) => const ImageCompressor());

/// 选图注入面：widget 测试覆盖为固定返回（不拉起系统选择器）。
final scanImagePickProvider = Provider<ScanImagePick>((ref) {
  final compressor = ref.watch(imageCompressorProvider);
  return (source) => compressor.pick(source,
      maxDim: kScanImageMaxDim, quality: kScanImageQuality);
});

/// 识菜入口全流程（M13-T7）：选来源 → 选图 → 识别 → 成功开确认表单 /
/// 失败弹提示。入口层（记一笔搜索弹层 / 我的食物库）只负责传 date/meal 与
/// recordMeal，不重复流程细节。
///
/// - 来源选择用 SimpleDialog「拍照 / 从相册选」（原生来源区分，H5 无此步，
///   R4 差异登记）；点外/返回取消 → null → 静默返回，零请求。
/// - 选图失败沿用既有选图口径（T5/T7 逐字）：「图片仍过大，请换一张」/
///   「图片处理失败」；选图本身取消（dataUrl=null）静默。
/// - 识别中对话框 barrierDismissible=false + PopScope 拦返回键（不可关闭）；
///   scanFood 抛错 → 关掉它再弹「识别失败：{msg||网络异常}」，「手动填写」
///   落既有自定义食物表单（date/meal 同入参），「取消」静默。
/// - 识别成功 → 关识别中 → showShiguangSheet 开 [FoodScanSheet]；宿主必须是
///   showShiguangSheet（T6 头注：保存链 toast 依赖根 Navigator Overlay）。
Future<void> openFoodScanFlow(
  BuildContext context,
  WidgetRef ref, {
  required String date,
  required String meal,
  bool recordMeal = true,
}) async {
  final source = await showDialog<ImageSource>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('识菜照片'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(ImageSource.camera),
          child: const Text('拍照'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(ImageSource.gallery),
          child: const Text('从相册选'),
        ),
      ],
    ),
  );
  if (source == null || !context.mounted) return; // 取消=静默

  final picked = await ref.read(scanImagePickProvider)(source);
  if (!context.mounted) return;
  if (picked.failure == ImagePickFailure.tooLargeEncoded) {
    _flowToast(context, '图片仍过大，请换一张');
    return;
  }
  if (picked.failure == ImagePickFailure.readFailed) {
    _flowToast(context, '图片处理失败');
    return;
  }
  final img = picked.dataUrl;
  if (img == null) return; // 选图取消=静默

  // M14-T5：读自带厂商配置（设备级密存）。读盘失败/未注入一律按未配置，
  // 回退内置通道——配置是可选增强，不能打断识菜主链路。
  AiProviderConfig? provider;
  try {
    provider = await ref.read(aiProviderStoreProvider).load();
  } catch (_) {
    provider = null;
  }
  if (!context.mounted) return;

  // 识别中（不可关闭）：根 navigator 上 push，关层时按同一 navigator 弹回。
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: EdgeInsets.all(Tokens.sp5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: Tokens.sp3),
              Text('识别中…', style: TextStyle(fontSize: Tokens.textMd)),
            ],
          ),
        ),
      ),
    ),
  );

  final Map<String, dynamic> scan;
  try {
    scan = await ref.read(healthApiProvider).scanFood(img, provider: provider);
  } catch (e) {
    navigator.pop(); // 关识别中
    if (!context.mounted) return;
    await _showScanError(context, ref, e, date: date, meal: meal);
    return;
  }
  navigator.pop(); // 关识别中
  if (!context.mounted) return;
  await showShiguangSheet<void>(
    context,
    title: '确认食物',
    child: FoodScanSheet(
      date: date,
      meal: meal,
      scan: scan,
      initialImage: img,
      recordMeal: recordMeal,
    ),
  );
}

/// 识菜失败提示（M13-T7）：「识别失败：{msg}」+「手动填写」/「取消」。
/// 手动填写落既有自定义食物表单，不另造入参面；取消静默零请求。
Future<void> _showScanError(
  BuildContext context,
  WidgetRef ref,
  Object error, {
  required String date,
  required String meal,
}) async {
  final msg = jsOr(error is ApiException ? error.message : null, '网络异常');
  final manual = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Tokens.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusLg)),
      content: Text('识别失败：$msg',
          style: const TextStyle(fontSize: Tokens.textMd, color: Tokens.ink2)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消',
              style: TextStyle(color: Tokens.ink3, fontSize: Tokens.textMd)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('手动填写',
              style: TextStyle(
                  color: Tokens.primaryDeep,
                  fontSize: Tokens.textMd,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  if (manual != true || !context.mounted) return;
  await openCustomFoodSheet(
    context,
    date: date,
    meal: meal,
    onSaved: () {}, // H5 无「识别失败→手动填」上游，落库后不发重查
  );
}

/// 入口层 toast（选图失败用）：走根 Overlay 的 SheetToast——两入口都处于
/// 弹层内，SnackBar 会被弹层遮挡（sheet_toast 头注定式）。
/// 入口层提示：同一时刻只保留一条，重复失败不叠两层（SheetToast 各自 2.4s 自删）。
OverlayEntry? _flowToastEntry;

void _flowToast(BuildContext context, String msg) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _flowToastEntry?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => SheetToast(
      msg: msg,
      onDone: () {
        if (entry.mounted) entry.remove();
        if (identical(_flowToastEntry, entry)) _flowToastEntry = null;
      },
    ),
  );
  _flowToastEntry = entry;
  overlay.insert(entry);
}

class FoodScanSheet extends ConsumerStatefulWidget {
  const FoodScanSheet({
    super.key,
    required this.date,
    required this.meal,
    required this.scan,
    required this.initialImage,
    this.recordMeal = true,
  });

  /// 记入目标日期（≙ 调用方上下文日期；食物库入口不记账时仅作占位）
  final String date;

  /// 记入目标餐次（breakfast/lunch/dinner/snack）
  final String meal;

  /// 云 /ai/food-scan 返回体：{dish,confidence,per100:{kcal,protein,carb,fat},...}
  final Map<String, dynamic> scan;

  /// 入库照片初值（= 本次识别图；可换可移除）
  final String initialImage;

  /// true=入库 + 记入本餐（记一笔入口）；false=只入库（食物库入口）
  final bool recordMeal;

  @override
  ConsumerState<FoodScanSheet> createState() => _FoodScanSheetState();
}

class _FoodScanSheetState extends ConsumerState<FoodScanSheet> {
  late final Map<String, dynamic> _per100 = () {
    final raw = widget.scan['per100'];
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
  }();

  late final TextEditingController _name =
      TextEditingController(text: '${widget.scan['dish'] ?? ''}'.trim());
  late final TextEditingController _grams =
      TextEditingController(text: '200'); // spec：默认 200g
  late final TextEditingController _kcal100 =
      TextEditingController(text: _initNum('kcal'));
  late final TextEditingController _protein100 =
      TextEditingController(text: _initNum('protein'));
  late final TextEditingController _carb100 =
      TextEditingController(text: _initNum('carb'));
  late final TextEditingController _fat100 =
      TextEditingController(text: _initNum('fat'));

  late String _image = widget.initialImage; // 入库照片，空串=不存图
  bool _busy = false; // 保存链在途（保存钮禁用 + 进行态）
  bool _picking = false; // 换图在途
  String? _error; // 入库失败文案（停留表单可重试）

  OverlayEntry? _toastEntry;

  bool get _lowConfidence => '${widget.scan['confidence']}' == 'low';

  /// 模型的一句话说明（可空）
  String get _note => '${widget.scan['note'] ?? ''}'.trim();

  /// 预填数字串形 ≙ JS 模板字符串（8.6→'8.6'、8.0→'8'，不漂 '8.0'）
  String _initNum(String key) {
    final v = _per100[key];
    return v is num ? jsNumText(v) : '0';
  }

  @override
  void dispose() {
    // 不在此摘 _toastEntry：保存成功/内置同名提示后本层立即 pop，toast 需
    // 随层关闭继续可读（H5 #toast 为全局元素），由 SheetToast.onDone 自删。
    _name.dispose();
    _grams.dispose();
    _kcal100.dispose();
    _protein100.dispose();
    _carb100.dispose();
    _fat100.dispose();
    super.dispose();
  }

  /// 层内 toast（SheetToast 定式，food_lib_sheet._toast 同形）
  void _toast(String msg) {
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

  /// 文本框 → 非负数（≙ H5 `Number(el.value) || 0`）。M13-T6 修复轮统一走
  /// jsNumber：与预填/其他表单同一套 JS 全串语义（'1.2.3'/空串按 0）。
  /// 实测 Dart 3.13.4 的 num.tryParse('160.') 同为 160，故本条是口径统一
  /// 而非修数值差；字符类已限 [0-9.]，Number 的 0x/Infinity 面不可达。
  static num _numOf(TextEditingController c) => jsNumber(c.text) ?? 0;

  int get _gramsValue => int.tryParse(_grams.text.trim()) ?? 0;

  Map<String, num> get _per100Values => <String, num>{
        'kcal': _numOf(_kcal100),
        'protein': _numOf(_protein100),
        'carb': _numOf(_carb100),
        'fat': _numOf(_fat100),
      };

  /// 实时汇总（spec §3.3 文案）：随克数/四项即时变。
  /// 数字串形走 jsNumText——与预填同一套 JS 模板语义，整值营养素显示
  /// `20g` 而非 Dart double 的 `20.0g`（H5 是 number 模板）。
  String get _totalText {
    final t = scanPortionTotals(_per100Values, _gramsValue);
    return '这份 ≈ ${jsNumText(t.kcal)} kcal · 蛋白 ${jsNumText(t.protein)}g / '
        '碳水 ${jsNumText(t.carb)}g / 脂肪 ${jsNumText(t.fat)}g';
  }

  /// 换入库照片（spec §3.2：仅换 image，不重新识别）
  Future<void> _pickPhoto() async {
    if (_busy || _picking) return;
    setState(() => _picking = true);
    try {
      final r = await ref.read(scanImagePickProvider)(ImageSource.gallery);
      if (!mounted) return;
      if (r.failure == ImagePickFailure.tooLargeEncoded) {
        _toast('图片仍过大，请换一张'); // 既有选图口径逐字
        return;
      }
      if (r.failure == ImagePickFailure.readFailed) {
        _toast('图片处理失败'); // 既有选图口径逐字
        return;
      }
      if (r.dataUrl == null) return; // 取消静默
      setState(() => _image = r.dataUrl!);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// 保存链（spec §3.4 顺序）：upsert →（未 skipped）失效缓存 →（记一笔入口）记账 → pop
  Future<void> _save() async {
    if (_busy) return;
    final name = _name.text.trim();
    final grams = _gramsValue;
    if (name.isEmpty) {
      _toast('请填写菜名');
      return;
    }
    if (grams < 1 || grams > 2000) {
      _toast('克数需在 1–2000 之间');
      return;
    }
    final t = scanPortionTotals(_per100Values, grams);
    final portion = '${grams}g';
    final image = _image;
    setState(() {
      _busy = true;
      _error = null;
    });

    final Map<String, dynamic> r;
    try {
      // 入库体按份营养（= 用户确认后的值）；meals 留空由后续归类决定
      r = await ref.read(healthApiProvider).upsertCustomFood(<String, dynamic>{
        'name': name,
        'kcal': t.kcal,
        'grams': grams,
        'unit': 'g',
        'meals': <String>[],
        'protein': t.protein,
        'carb': t.carb,
        'fat': t.fat,
        'portion': portion,
        'image': image,
      });
    } catch (e) {
      // 入库失败：停留表单、保留输入可重试，不记账（spec §3.4-5）
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            '保存失败：${jsOr(e is ApiException ? e.message : null, '网络异常')}';
      });
      return;
    }

    // 入库回包前用户关层（✕/下滑）：不再记账/弹层内 toast（ref 已失效）。
    if (!mounted) return;
    final skippedBuiltin = r['skipped'] == 'builtin';
    if (skippedBuiltin) {
      // 内置库已有同名：本轮未写自定义库 → 不失效缓存，但照常记账
      _toast('内置库已有「$name」，本条未重复入库');
    } else {
      // M9 写路径「先删键再刷新」+ M11 搜索快照失效（同 food_lib/custom_food 链）
      ref.read(swrCacheProvider).invalidate('foods.custom');
      invalidateFoodLibrary(ref);
    }

    if (widget.recordMeal) {
      try {
        await ref.read(recordControllerProvider).addRecord(
          widget.date,
          <String, dynamic>{
            'date': widget.date,
            'meal': widget.meal,
            'name': name,
            'portion': portion,
            'kcal': t.kcal,
            'emoji': r['emoji'] ?? '🍽️',
            'image': image,
            'protein': t.protein,
            'carb': t.carb,
            'fat': t.fat,
          },
          pendingKey:
              'scan:${name}_${DateTime.now().millisecondsSinceEpoch}',
        );
      } catch (e) {
        // 入库已成功（不重复入库）；仅本餐记入失败，仍关层。
        // spec §3.4-4 文案带原因；用户在在途关层时 State 已销毁，_toast 走
        // Overlay.of(context) 会抛，故 mounted 守卫后再 toast。
        if (mounted) {
          _toast('已入库，本餐记入失败：'
              '${jsOr(e is ApiException ? e.message : null, '网络异常')}');
        }
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  static const _label =
      TextStyle(fontSize: Tokens.textSm, fontWeight: FontWeight.w700, color: Tokens.ink);
  static const _sub = TextStyle(fontSize: Tokens.textXs, color: Tokens.ink3);

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        counterText: '',
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 键盘上滚（表单可滚到保存钮）
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            Tokens.sp5, Tokens.sp3, Tokens.sp5, Tokens.sp4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 入库照片（spec §3.3 顶部；默认=识别图）
            const Text('入库照片', style: _label),
            const Text('默认用识别图；换图不重新识别', style: _sub),
            const SizedBox(height: Tokens.sp1),
            Row(
              children: [
                // 有图画图、坏图/空图回退 🍽️（FoodThumb 既有语义）
                FoodThumb(source: _image, emoji: '🍽️', size: 56),
                const SizedBox(width: Tokens.sp3),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: scanPickPhotoKey,
                          onPressed:
                              _busy || _picking ? null : _pickPhoto,
                          child: Text(_picking ? '选图中…' : '从本地选一张'),
                        ),
                      ),
                      const SizedBox(width: Tokens.sp2),
                      OutlinedButton(
                        key: scanRemovePhotoKey,
                        onPressed: _busy || _picking || _image.isEmpty
                            ? null
                            : () => setState(() => _image = ''),
                        child: const Text('移除'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_lowConfidence) ...[
              const SizedBox(height: Tokens.sp2),
              // spec §3.3：low → 黄字提示
              const Text('识别把握不大，请核对菜名与数值',
                  style: TextStyle(fontSize: Tokens.textSm, color: Tokens.warn)),
            ],
            if (_note.isNotEmpty) ...[
              const SizedBox(height: Tokens.sp1),
              // 模型的一句话说明（如「偏油」「含较多汤汁」），只作参考
              Text('识别备注：$_note',
                  style: const TextStyle(
                      fontSize: Tokens.textXs, color: Tokens.ink3)),
            ],
            const SizedBox(height: Tokens.sp3),
            // 菜名（预填模型建议，可改）
            const Text('菜名', style: _label),
            const SizedBox(height: Tokens.sp1),
            TextField(
              controller: _name,
              key: scanNameKey,
              maxLength: 30,
              enabled: !_busy,
              decoration: _field('如：蒜薹鸡块'),
            ),
            const SizedBox(height: Tokens.sp3),
            // 克数（默认 200g，1–2000）
            const Text('这一份克数', style: _label),
            const SizedBox(height: Tokens.sp1),
            TextField(
              controller: _grams,
              key: scanGramsKey,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: _field('如：200').copyWith(suffixText: 'g'),
            ),
            const SizedBox(height: Tokens.sp3),
            // 每 100g 四项（可改，非负）
            const Text('每 100g 营养', style: _label),
            const Text('AI 估算，可修改；保存的以你确认的值为准', style: _sub),
            const SizedBox(height: Tokens.sp1),
            Row(
              children: [
                _macroField('热量', _kcal100, scanKcalKey, 'kcal'),
                const SizedBox(width: Tokens.sp2),
                _macroField('蛋白', _protein100, scanProteinKey, 'g'),
                const SizedBox(width: Tokens.sp2),
                _macroField('碳水', _carb100, scanCarbKey, 'g'),
                const SizedBox(width: Tokens.sp2),
                _macroField('脂肪', _fat100, scanFatKey, 'g'),
              ],
            ),
            const SizedBox(height: Tokens.sp3),
            // 实时汇总（随克数/四项即时变）
            Text(_totalText,
                key: scanTotalKey,
                style: const TextStyle(
                    fontSize: Tokens.textSm,
                    fontWeight: FontWeight.w700,
                    color: Tokens.primaryDeep)),
            if (widget.recordMeal) ...[
              const SizedBox(height: Tokens.sp1),
              Text('保存后记入${mealNames[widget.meal] ?? '本餐'}',
                  style: _sub),
            ],
            if (_error != null) ...[
              const SizedBox(height: Tokens.sp2),
              Text(_error!,
                  style:
                      const TextStyle(fontSize: Tokens.textSm, color: Tokens.danger)),
            ],
            const SizedBox(height: Tokens.sp4),
            FilledButton(
              key: scanSaveKey,
              onPressed: _busy ? null : _save,
              child: Text(_busy ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _macroField(String label, TextEditingController ctl, Key key, String unit) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 单位并进标签：四个输入框等分后每个仅约 70dp，`suffixText:'kcal'`
          // 会把可输入区压到 1 位数宽（真机实测 62 显示成 6），故把单位移出输入框。
          Text('$label($unit)', style: _sub),
          const SizedBox(height: Tokens.sp1),
          TextField(
            controller: ctl,
            key: key,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: (_) => setState(() {}),
            decoration: _field('0'),
          ),
        ],
      ),
    );
  }
}
