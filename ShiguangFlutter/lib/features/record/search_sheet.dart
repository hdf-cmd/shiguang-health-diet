// ShiguangFlutter/lib/features/record/search_sheet.dart
// 「记一笔」食物搜索弹层（M2 Task 9）。
// 行为权威源 js/app.js:615-712：openSheet 即搜空关键词（618）、200ms 防抖
// （696-700）、结果行「名/meta/kcal + 按钮」（634-643，per100→「按克加」、
// unit=ml→「按毫升加」、普通→「添加」）、加载态「搜索中...」（631）、
// 空结果「没找到「kw」/换个说法，或添加自定义食物」（644-645）、
// 失败「搜索失败：msg」+「重试」（648-649）、添加成功 toast
// 「已添加 X · 可继续添加」（676）、body 字段（678-682）、
// 点击后按钮 disabled 防连点直到请求结束（677/693 → pending 期禁用 +「请稍候…」，
// 文案同 H5 提交态 js/app.js:1902）。
// 与 H5 差异：弹层内餐次分段移到记录页顶部（简报）。自定义食物两处入口均已
// 接线（spec D1「空结果处 + 搜索框旁，H5 同位」）：空结果「＋ 自定义食物」
// （cf-open，js/app.js:645-646/657-658，M5-T7）+ 搜索框旁常驻「＋ 自定义」
// （≙ index.html:276 #sheet-cf-open；点击 ≙ js/app.js:1275
// openCustomFoodSheet() 无 fromLib：initialName=当时关键词 :1208、无关键词
// 为空，meal=当前餐次，双保存钮齐全；M5 终审 F2 补漏）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/constants.dart';
import '../common/food_thumb.dart';
import '../common/sheet.dart' show showShiguangSheet;
import '../common/skeleton.dart' show SkeletonBar;
import 'custom_food_sheet.dart';
import 'food_scan_sheet.dart' show openFoodScanFlow;
import 'freq_loading_strip.dart';
import 'portion_sheet.dart';
import 'food_freq.dart';
import 'record_controller.dart';

Future<void> showSearchSheet(
  BuildContext context, {
  required String date,
  required String meal,
}) {
  // M9-T8：开层样板收口 showShiguangSheet；弹层标题「记一笔 · <餐次>」
  // （js/app.js:613）原在层内首行，现逐字上移为 helper 标题。
  return showShiguangSheet<void>(
    context,
    title: '记一笔 · ${mealNames[meal] ?? ''}',
    child: SearchSheet(date: date, meal: meal),
  );
}

class SearchSheet extends ConsumerStatefulWidget {
  const SearchSheet({super.key, required this.date, required this.meal});

  final String date;
  final String meal;

  @override
  ConsumerState<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<SearchSheet> {
  final TextEditingController _input = TextEditingController();
  Timer? _debounce;

  /// 已生效关键词（H5 state.sheetKeyword 语义）：初始 ''，openSheet 即出结果
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    // 常吃排序（方案 B）：开弹层触发一次性历史初始化（幂等、不阻塞渲染；
    // 计数就绪后 searchProvider watch foodFreqProvider 自动重排）。
    // 旁路降级：初始化失败（无网络/无注入）本次按云端原序显示，不打断记餐。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref
            .read(foodFreqProvider.notifier)
            .ensureLoaded()
            .catchError((Object _) {}));
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  /// H5 200ms 防抖（js/app.js:696-700）
  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _keyword = v);
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 在途键：食物 id（缺 id 退化为 name），与份量弹层同键 → 同一食物的
  /// 「添加」/「按克加」共享 pending 状态（H5 是按 DOM 上的那一个按钮 disabled）。
  String _pendingKey(Map<String, dynamic> f) =>
      '${f['id'] ?? f['name'] ?? ''}';

  /// 按钮禁用/文案的在途判定：状态只存在 RecordController 一处，
  /// 本方法每次 build 读一次（重绘由 _addFood 前后的 setState 驱动）。
  bool _pending(Map<String, dynamic> f) =>
      ref.read(recordControllerProvider).isInFlight(_pendingKey(f));

  /// 普通食物直接记一笔：body 字段对齐 js/app.js:678-682（portion=f.meta）
  Future<void> _addFood(Map<String, dynamic> f) async {
    final controller = ref.read(recordControllerProvider);
    final pendingKey = _pendingKey(f);
    if (controller.isInFlight(pendingKey)) return; // H5 js/app.js:677 btn.disabled
    final body = <String, dynamic>{
      'date': widget.date,
      'meal': widget.meal,
      'name': f['name'] ?? '',
      'portion': f['meta'] ?? '',
      'kcal': f['kcal'] ?? 0,
      'emoji': f['emoji'] ?? '',
      'protein': f['protein'] ?? 0,
      'carb': f['carb'] ?? 0,
      'fat': f['fat'] ?? 0,
      'image': f['image'] ?? '',
    };
    final pending =
        controller.addRecord(widget.date, body, pendingKey: pendingKey);
    // addRecord 的乐观落位与在途登记都在同步段完成，此处重绘即得新数据。
    if (mounted) setState(() {});
    // M11-T2：toast 移到乐观位之后、回包之前（≙ H5 js/app.js:677「已添加 …
    // 可继续添加」先响，失败再补一条「添加失败」）。同键在途的丢弃支由上面
    // isInFlight 预检拦住（H5 靠 btn.disabled，同形），故此处不再判返回值。
    _toast('已添加 ${f['name'] ?? ''} · 可继续添加');
    try {
      await pending;
    } on ApiException catch (e) {
      _toast('添加失败：${e.message}');
    } catch (_) {
      _toast('添加失败：网络异常');
    } finally {
      if (mounted) setState(() {}); // 在途解除，恢复按钮（H5 js/app.js:693）
    }
  }

  /// ≙ :1251 fillSheetResults(state.sheetKeyword)：以当时关键词重查
  /// （invalidate 同键 family）。cf-open 空结果入口与常驻 sheet-cf-open
  /// 共用。差异登记见 custom_food_sheet.dart onSaved 调用处注释。
  void _requeryResults() =>
      ref.invalidate(searchProvider((keyword: _keyword, meal: widget.meal)));

  @override
  Widget build(BuildContext context) {
    final query = (keyword: _keyword, meal: widget.meal);
    final results = ref.watch(searchProvider(query));
    // M12-④：行尾「吃过 N 次」——与常吃排序同一份全史计数
    final counts = ref.watch(foodFreqProvider);

    // M9-T8：弹层标题「记一笔 · <餐次>」+ ✕（原 ValueKey('sheet-close')
    // IconButton，tooltip「关闭」）由 showShiguangSheet 标题行承载，本地
    // 副本删除；内层 SafeArea 与 helper 重复去内层留 helper 的；0.72h 内容
    // 高经 helper Flexible 槽承接（超 78% 上限按约束回缩，Expanded 列表自适应）。
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.sp4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              const SizedBox(height: Tokens.sp2),
              // 搜索框行 + 常驻「＋ 自定义」钮（≙ index.html:276
              // #sheet-cf-open，文案逐字；点击 ≙ js/app.js:1275
              // openCustomFoodSheet()：initialName=当时关键词（:1208，无关键
              // 词为空）、meal=当前餐次、date=弹层入参（结转 A①同源）。
              // 布局：输入框 Expanded 收弹性、钮取固有紧凑 outlined 样式，
              // 防挤掉输入框（theme minimumSize 已收口 Size(0,52) 有限值）。
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      onChanged: _onChanged,
                      decoration:
                          const InputDecoration(hintText: '搜索食物库'),
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                  const SizedBox(width: Tokens.sp2),
                  // M13-T7：拍照识菜入口（简报 key sheet-scan-open）。记一笔
                  // 入口 recordMeal=true——date/meal 用弹层入参（≙ 本弹层其他
                  // 记入同源，消跨午夜双轨）。识别成功由 openFoodScanFlow 以
                  // showShiguangSheet 打开确认表单，盖在本弹层之上。
                  IconButton(
                    key: const ValueKey('sheet-scan-open'),
                    tooltip: '拍照识菜',
                    icon: const Icon(Icons.photo_camera_outlined),
                    onPressed: () => openFoodScanFlow(
                      context,
                      ref,
                      date: widget.date,
                      meal: widget.meal,
                    ),
                  ),
                  OutlinedButton(
                    key: const ValueKey('sheet-cf-open'),
                    onPressed: () => openCustomFoodSheet(
                      context,
                      date: widget.date,
                      meal: widget.meal,
                      initialName: _keyword,
                      onSaved: _requeryResults,
                    ),
                    child: const Text('＋ 自定义', // index.html:276 逐字
                        style: TextStyle(
                            fontSize: Tokens.textSm,
                            color: Tokens.primaryDeep)),
                  ),
                ],
              ),
              const FreqLoadingStrip(),
              Expanded(
                child: results.when(
                  loading: () => const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('搜索中...',
                          style: TextStyle(
                              color: Tokens.ink3, fontSize: Tokens.textSm)),
                      SizedBox(height: Tokens.sp3),
                      SkeletonBar(height: 64),
                      SizedBox(height: Tokens.sp2),
                      SkeletonBar(height: 64),
                      SizedBox(height: Tokens.sp2),
                      SkeletonBar(height: 64),
                    ],
                  ),
                  error: (e, _) {
                    final msg = e is ApiException ? e.message : '网络异常';
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('搜索失败：$msg',
                              style: const TextStyle(
                                  color: Tokens.danger,
                                  fontSize: Tokens.textSm)),
                          const SizedBox(height: Tokens.sp2),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(searchProvider(query)),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    );
                  },
                  data: (foods) => foods.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('🔍',
                                  style: TextStyle(fontSize: Tokens.textXl)),
                              const SizedBox(height: Tokens.sp2),
                              Text('没找到「$_keyword」',
                                  style: const TextStyle(
                                      fontSize: Tokens.textMd,
                                      fontWeight: FontWeight.w700,
                                      color: Tokens.ink)),
                              const SizedBox(height: Tokens.sp1),
                              const Text('换个说法，或添加自定义食物',
                                  style: TextStyle(
                                      fontSize: Tokens.textSm,
                                      color: Tokens.ink3)),
                              // 空结果入口（js/app.js:645-646 #cf-open）：开
                              // 自定义食物表单，初始名=当时关键词（:1208）；
                              // onSaved ≙ :1251 fillSheetResults(sheetKeyword)
                              // 重查（_requeryResults；H5 仅入库分支重查，
                              // Flutter 两分支统一，差异登记见该处注释）。
                              // date=弹层入参日期（M5-T8 结转 A①：记入日与
                              // 本弹层其他记入同源，消跨午夜 todayIso 双轨）。
                              OutlinedButton(
                                key: const ValueKey('cf-open'),
                                onPressed: () => openCustomFoodSheet(
                                  context,
                                  date: widget.date,
                                  meal: widget.meal,
                                  initialName: _keyword,
                                  onSaved: _requeryResults,
                                ),
                                child: const Text('＋ 自定义食物', // :646 逐字
                                    style: TextStyle(
                                        fontSize: Tokens.textSm,
                                        color: Tokens.primaryDeep)),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: foods.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: Tokens.sp2),
                          itemBuilder: (_, i) => _foodTile(foods[i], counts),
                        ),
                ),
              ),
              const SizedBox(height: Tokens.sp3),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
    );
  }

  /// 结果行：emoji/缩略 + 名 + meta + kcal + 动作按钮
  /// （js/app.js:634-643）
  Widget _foodTile(Map<String, dynamic> f, Map<String, int> counts) {
    final isPer100 = f['per100'] is Map;
    final actionText =
        isPer100 ? (f['unit'] == 'ml' ? '按毫升加' : '按克加') : '添加';
    final kcal = (f['kcal'] as num?) ?? 0;
    final eaten = counts['${f['name'] ?? ''}'] ?? 0; // M12-④ 全史次数
    return Container(
      padding: const EdgeInsets.all(Tokens.sp3),
      decoration: BoxDecoration(
        color: Tokens.surface2,
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
        border: Border.all(color: Tokens.line),
      ),
      child: Row(
        children: [
          // 缩略图位（js/app.js:637 f.image ? img : f.emoji）：M5-T4 FoodThumb，
          // 无图/坏图回退 emoji；尺寸 40 先按 H5 .thumb 观感，目检后可调（R4）。
          FoodThumb(
            source: (f['image'] as String?) ?? '',
            emoji: (f['emoji'] as String?) ?? '🍽️',
          ),
          const SizedBox(width: Tokens.sp3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${f['name'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: Tokens.textMd,
                      fontWeight: FontWeight.w700,
                      color: Tokens.ink),
                ),
                const SizedBox(height: Tokens.sp1),
                Text(
                  // M12-④：次数**放在 meta 前**——搜索行右侧被 kcal+按钮占满，
                  // 名字列仅 ~110dp，次数跟在 meta 后面会被省略号吃掉（真机实测
                  // 「吃过…」看不见数字）；放在前面则先舍 meta 尾巴、数字恒可见。
                  eaten > 0
                      ? (('${f['meta'] ?? ''}').isEmpty
                          ? '吃过 $eaten 次'
                          : '吃过 $eaten 次 · ${f['meta']}')
                      : '${f['meta'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(width: Tokens.sp2),
          Text(
            '${kcal.round()} kcal',
            style: const TextStyle(
                fontSize: Tokens.textSm,
                fontWeight: FontWeight.w700,
                color: Tokens.ink2),
          ),
          const SizedBox(width: Tokens.sp2),
          TextButton(
            key: ValueKey('food-action-${f['id']}'),
            // pending 期禁用并显示「请稍候…」（H5 js/app.js:677 btn.disabled、
            // 1902 提交态文案）；重绘由 _addFood 前后 setState 驱动，
            // 完成/失败后恢复可点（js/app.js:693 finally btn.disabled = false）。
            onPressed: _pending(f)
                ? null
                : () => isPer100
                    ? showPortionSheet(context,
                        food: f, date: widget.date, meal: widget.meal)
                    : _addFood(f),
            child: Text(_pending(f) ? '请稍候…' : actionText),
          ),
        ],
      ),
    );
  }
}
