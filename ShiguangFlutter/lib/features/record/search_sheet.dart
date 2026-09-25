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
// 与 H5 差异：弹层内餐次分段移到记录页顶部（简报）。「＋ 自定义食物」空结果
// 入口 M5-T7 已接线（cf-open，js/app.js:645-646/657-658）；H5 记一笔弹层头部
// 的常驻「＋ 自定义」钮（index.html:276 #sheet-cf-open）简报范围外未接，登记报告。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/constants.dart';
import '../common/food_thumb.dart';
import 'custom_food_sheet.dart';
import 'portion_sheet.dart';
import 'food_freq.dart';
import 'record_controller.dart';

Future<void> showSearchSheet(
  BuildContext context, {
  required String date,
  required String meal,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(Tokens.radiusSheet)),
    ),
    builder: (_) => SearchSheet(date: date, meal: meal),
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
    // addRecord 同步登记在途后立即重绘 → pending 期按钮禁用 +「请稍候…」
    if (mounted) setState(() {});
    try {
      // false = 同键重复提交被控制器丢弃（理论上已被禁用拦住），不出 toast
      if (await pending) _toast('已添加 ${f['name'] ?? ''} · 可继续添加');
    } on ApiException catch (e) {
      _toast('添加失败：${e.message}');
    } catch (_) {
      _toast('添加失败：网络异常');
    } finally {
      if (mounted) setState(() {}); // 在途解除，恢复按钮（H5 js/app.js:693）
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = (keyword: _keyword, meal: widget.meal);
    final results = ref.watch(searchProvider(query));

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Padding(
          padding: const EdgeInsets.all(Tokens.sp4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 弹层标题「记一笔 · <餐次>」（js/app.js:613）
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '记一笔 · ${mealNames[widget.meal] ?? ''}',
                      style: const TextStyle(
                          fontSize: Tokens.textLg,
                          fontWeight: FontWeight.w800,
                          color: Tokens.ink),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('sheet-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Tokens.ink3),
                    tooltip: '关闭',
                  ),
                ],
              ),
              const SizedBox(height: Tokens.sp2),
              TextField(
                controller: _input,
                onChanged: _onChanged,
                decoration: const InputDecoration(hintText: '搜索食物库'),
                textInputAction: TextInputAction.search,
              ),
              const SizedBox(height: Tokens.sp3),
              Expanded(
                child: results.when(
                  loading: () => const Center(
                    child: Text('搜索中...',
                        style: TextStyle(color: Tokens.ink3)),
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
                              // = 以当前关键词重查（invalidate 同键 family）。
                              OutlinedButton(
                                key: const ValueKey('cf-open'),
                                onPressed: () => openCustomFoodSheet(
                                  context,
                                  meal: widget.meal,
                                  initialName: _keyword,
                                  onSaved: () => ref.invalidate(
                                      searchProvider((
                                        keyword: _keyword,
                                        meal: widget.meal,
                                      ))),
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
                          itemBuilder: (_, i) => _foodTile(foods[i]),
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
      ),
    );
  }

  /// 结果行：emoji/缩略 + 名 + meta + kcal + 动作按钮
  /// （js/app.js:634-643）
  Widget _foodTile(Map<String, dynamic> f) {
    final isPer100 = f['per100'] is Map;
    final actionText =
        isPer100 ? (f['unit'] == 'ml' ? '按毫升加' : '按克加') : '添加';
    final kcal = (f['kcal'] as num?) ?? 0;
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
                  '${f['meta'] ?? ''}',
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
