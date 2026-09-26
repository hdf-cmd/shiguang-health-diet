// ShiguangFlutter/lib/features/profile/food_lib_sheet.dart
// M7-T4「我的食物库」管理弹层：自定义食物归类/删除 + 内置常菜移除/恢复。
// 行为权威源 js/app.js:1288-1398（openFoodLib/renderLibList/#lib-list 事件族）
// + index.html:561-575（lib-sheet DOM），逐字口径：
// - 开层（openFoodLib :1292-1298）：libTab 复位 custom → renderLibList
//   （先「加载中…」再取数）。内置 tab 数据经 libBuiltinCache（:1290/:1322）
//   只取一次；自定义每次 renderLibList 重取（:1308）。
// - 双 tab（index.html:570-571）：「我的自定义」「内置常菜」；sub 行
//   「自定义 N 条 · 点餐次标签可改归类」(:1309) / 「内置 N 条 · 已移除 M」
//   (:1324)（H5 #foodlib-sub 不在 DOM 里，失败/在途时保留上一成功值——
//   Flutter 以 _sub 态等价）。
// - 自定义行（:1310-1319）：thumb(图||emoji||🍽️) + 名 + meta
//   `${grams?grams+unit+' · ':''}${kcal} kcal · 蛋白 Xg / 碳水 Yg / 脂肪 Zg`
//   (:1315) + 三枚餐次钮（早餐/正餐/零食，cfMealKind 高亮 :1178-1185）+ 删除钮。
// - 归类（:1357-1365）：点按 → setCustomFoodMeals(id, CF_MEAL_MAP[kind])
//   （lunch/dinner 同归「正餐」文案，:1362 三态）→ 成功 toast
//   「已归到X · 搜索时只在对应餐次出现」+ renderLibList 重取；失败
//   「设置失败：msg||网络异常」+ 钮复位。
// - 删除（:1367-1377）：showConfirm('删除自定义食物','删除后不可恢复；已记录的
//   饮食不受影响。') → 取消零请求；确认 → deleteCustomFood(裸 id) → toast
//   「已删除」+ 重取；失败「删除失败：msg」。确认样式沿用删餐/删运动同族
//   AlertDialog（exercise_sheet.dart:78-111 定式；通用 confirm 抽取归 T8 卫生批，
//   本批不碰 T2 文件）。
// - 内置 toggle（:1379-1396）：钮「移除/恢复」二态；提交 setHiddenFoods(全量
//   hidden ids ≙ :1385-1391 现 hidden 集 +本条/摘本条)；成功后本地 cache 翻转
//   (:1392) 不重取；toast「已移除「名」/已恢复「名」」(:1394)；失败
//   「操作失败：msg」钮态不变。
// - 加载失败（:1338）：「⚠️ 加载失败：msg||网络异常」+「重试」钮（#lib-retry）。
// - 自定义空态（:1320）：「还没有自定义食物\n点下方按钮添加你的常吃菜」。
// id 语义：listCustomFoods 回裸 _id（云 index.js:300），归类/删除提交原样透传，
// 不经搜索结果 cf_ 前缀路径（index.js:82 只在 /foods/search 拼前缀）——回归钉⑨。
// R4 差异登记（修复轮 1 更新）：#lib-add「＋ 添加自定义食物」（index.html:574，
// 层底常驻、双 tab/加载/失败态均在；点击 ≙ js/app.js:1347 closeFoodLib() →
// openCustomFoodSheet(true)）本批已补——落点：openFoodLibSheet 收到 pop(true)
// 后关层再开表单（date=当日 todayIso、meal=默认档 lunch「正餐」，评审裁定）。
// 缺口登记：表单仍为双钮完整形态，fromLib 单钮「存入食物库」+隐藏次钮
// （js/app.js:1220-1221）未做，结转 T8；视觉（seg/chip/行族）
// 为 R4 创新，文案逐字。toast 走层内 OverlayEntry（SheetToast 公共件，M6-T7 F5
// 定式：SnackBar 会被弹层遮挡并向下层 Scaffold 广播双份）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/dates.dart' show todayIso;
import '../../domain/js_compat.dart' show jsNumText, jsOr;
import '../common/food_thumb.dart';
import '../common/sheet_toast.dart';
import '../home/home_controller.dart' show healthApiProvider;
import '../record/custom_food_sheet.dart' show cfMealMap, openCustomFoodSheet;

@visibleForTesting
const libCloseKey = Key('lib-close'); // index.html:567 #lib-close

@visibleForTesting
Key libSegKey(String tab) => Key('lib-seg-$tab'); // :569 #lib-seg 双钮

@visibleForTesting
const libSubKey = Key('lib-sub'); // :1309/:1324 sub 文案位

@visibleForTesting
Key libMealKey(String id, String kind) => Key('lib-meal-$id-$kind'); // :1316 data-set-cf-meal

@visibleForTesting
Key libDelKey(String id) => Key('lib-del-$id'); // :1318 data-del-cf

@visibleForTesting
Key libTogKey(String id) => Key('lib-tog-$id'); // :1333 data-toggle-builtin

@visibleForTesting
const libRetryKey = Key('lib-retry'); // :1339 #lib-retry

@visibleForTesting
const libAddKey = Key('lib-add'); // index.html:574 #lib-add（层底常驻钮）

/// kind 三档（:1316 渲染序）→ 钮文案（早餐/正餐/零食，逐字）
const _kindLabels = <String, String>{
  'breakfast': '早餐',
  'lunch': '正餐',
  'snack': '零食',
};

/// 反查归类高亮档（cfMealKind js/app.js:1178-1185 逐支翻译，bug-for-bug）：
/// 未归类/未知组合返回空串（全钮不亮）
@visibleForTesting
String cfMealKind(Object? meals) {
  if (meals is! List || meals.isEmpty) return '';
  final s = meals.join(',');
  if (s == 'breakfast') return 'breakfast';
  if (s == 'snack') return 'snack';
  if (meals.contains('lunch') || meals.contains('dinner')) return 'lunch';
  return '';
}

/// 打开「我的食物库」管理弹层（≙ openFoodLib，js/app.js:1292）。
/// 层底「＋ 添加自定义食物」（#lib-add）点按 pop 带回 true ≙ :1347
/// closeFoodLib() → openCustomFoodSheet(true)：关层后开自定义食物表单
/// （date=当日、meal=默认档正餐；fromLib 单钮形态结转 T8，见头注 R4 登记）。
Future<void> openFoodLibSheet(BuildContext context) async {
  final addRequested = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(Tokens.radiusSheet)),
    ),
    builder: (_) => const _FoodLibSheet(),
  );
  if (addRequested == true) {
    if (!context.mounted) return; // 层动画期间入口页可能已销毁
    await openCustomFoodSheet(
      context,
      date: todayIso(), // ≙ H5 :1244 在途常读全局 state.date=当日（我的页无选日态）
      meal: 'lunch', // 默认档（评审裁定：本批 meal 可默认档；三钮初值=正餐 :1218）
      onSaved: () {}, // H5 入库后不重开管理层；下次开层 renderLibList 天然重取
    );
  }
}

class _FoodLibSheet extends ConsumerStatefulWidget {
  const _FoodLibSheet();

  @override
  ConsumerState<_FoodLibSheet> createState() => _FoodLibSheetState();
}

class _FoodLibSheetState extends ConsumerState<_FoodLibSheet> {
  // openFoodLib :1293：每次开层复位自定义 tab（弹层态随路由销毁，天然一致）
  String _tab = 'custom';
  bool _loading = true;
  String? _error; // ≙ renderLibList catch 支文案（已 ||网络异常 兜底）
  List<dynamic> _custom = const <dynamic>[];

  /// ≙ let libBuiltinCache（:1290）：null=未取过；内置 tab 只发一次请求
  List<dynamic>? _builtinCache;

  /// 在途动作集（≙ 被点钮 disabled=true，:1359/:1371/:1389；失败复位）
  final Set<String> _busy = <String>{};

  /// sub 行：仅成功渲染时更新（:1309/:1324；失败/在途保留上一成功值 ≙ H5
  /// #foodlib-sub 只在成功路径 textContent 赋值）
  String? _sub;

  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    _render(); // ≙ openFoodLib 尾行 renderLibList()
  }

  @override
  void dispose() {
    _toastEntry?.remove(); // toast 随层销毁
    super.dispose();
  }

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

  /// renderLibList（:1303-1341）：先「加载中…」占位，再按 tab 取数渲染。
  Future<void> _render() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_tab == 'custom') {
        final list =
            await ref.read(healthApiProvider).listCustomFoods();
        if (!mounted) return;
        setState(() {
          _custom = list;
          _loading = false;
          _sub = '自定义 ${list.length} 条 · 点餐次标签可改归类'; // :1309 逐字
        });
      } else {
        final list = _builtinCache ??
            await ref
                .read(healthApiProvider)
                .getBuiltinFoods(); // :1322 ||短路（cache 在场不重取）
        _builtinCache = list;
        if (!mounted) return;
        final hiddenCount =
            list.where((f) => f is Map && f['hidden'] == true).length;
        setState(() {
          _loading = false;
          _sub = '内置 ${list.length} 条 · 已移除 $hiddenCount'; // :1324 逐字
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = jsOr(e.message, '网络异常'); // :1338 e.message||'网络异常'
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '网络异常';
        _loading = false;
      });
    }
  }

  void _selectTab(String tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab); // #lib-seg 点按 :1348-1353
    _render();
  }

  /// 归类点按链（:1356-1365）
  Future<void> _setMeal(String id, String kind) async {
    final key = 'meal:$id:$kind';
    if (_busy.contains(key)) return;
    _busy.add(key); // mealChip.disabled = true
    try {
      await ref
          .read(healthApiProvider)
          .setCustomFoodMeals(id, cfMealMap[kind] ?? const <String>[]);
      if (!mounted) return;
      // :1362 三态文案：breakfast→早餐 / snack→零食 / 其余(lunch 档，含 dinner)→正餐
      _toast('已归到${_kindLabels[kind] ?? '正餐'} · 搜索时只在对应餐次出现');
      await _render(); // :1363 成功后重取
    } on ApiException catch (e) {
      if (mounted) _toast('设置失败：${jsOr(e.message, '网络异常')}'); // :1364
    } catch (_) {
      if (mounted) _toast('设置失败：网络异常');
    } finally {
      _busy.remove(key); // 失败支 disabled=false 复位（成功支随重取重建）
    }
  }

  /// 删除链（:1367-1377）：确认弹层 → DELETE → toast → 重取
  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Tokens.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusLg)),
        title: const Text('删除自定义食物', // :1369 标题逐字
            style: TextStyle(
                fontSize: Tokens.textLg,
                fontWeight: FontWeight.w700,
                color: Tokens.ink)),
        content: const Text('删除后不可恢复；已记录的饮食不受影响。', // :1369 逐字
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
            child: const Text('确认删除', // index.html:330 #confirm-ok 逐字
                style: TextStyle(
                    color: Tokens.danger,
                    fontSize: Tokens.textMd,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return; // 取消/点外零请求（:1370）
    final key = 'del:$id';
    if (_busy.contains(key)) return;
    _busy.add(key); // del.disabled = true
    try {
      await ref.read(healthApiProvider).deleteCustomFood(id);
      if (!mounted) return;
      _toast('已删除'); // :1374 逐字
      await _render(); // :1375
    } on ApiException catch (e) {
      if (mounted) _toast('删除失败：${jsOr(e.message, '网络异常')}'); // :1376
    } catch (_) {
      if (mounted) _toast('删除失败：网络异常');
    } finally {
      _busy.remove(key);
    }
  }

  /// 内置移除/恢复（:1379-1396）：全量 ids 提交 → 成功本地翻转 cache 不重取
  Future<void> _toggleBuiltin(Map<dynamic, dynamic> item) async {
    final id = '${item['id']}';
    final key = 'tog:$id';
    if (_busy.contains(key)) return;
    _busy.add(key); // tog.disabled = true
    try {
      final wasHidden = item['hidden'] == true;
      // :1385-1388：现 hidden 集全量 + 本条摘除/追加（全量替换语义）
      final ids = <String>[
        for (final f in _builtinCache ?? const <dynamic>[])
          if (f is Map && f['hidden'] == true) '${f['id']}',
      ];
      if (wasHidden) {
        ids.remove(id);
      } else if (!ids.contains(id)) {
        ids.add(id);
      }
      await ref.read(healthApiProvider).setHiddenFoods(ids);
      if (!mounted) return;
      item['hidden'] = !wasHidden; // :1392 本地 cache 翻转（不发重取）
      final hiddenCount =
          (_builtinCache ?? const <dynamic>[]).where((f) => f is Map && f['hidden'] == true).length;
      setState(() =>
          _sub = '内置 ${(_builtinCache ?? const <dynamic>[]).length} 条 · 已移除 $hiddenCount'); // :1393 renderLibList（cache 支零请求）
      _toast(wasHidden
          ? '已恢复「${item['name']}」' // :1394 逐字
          : '已移除「${item['name']}」');
    } on ApiException catch (e) {
      if (mounted) _toast('操作失败：${jsOr(e.message, '网络异常')}'); // :1395
    } catch (_) {
      if (mounted) _toast('操作失败：网络异常');
    } finally {
      _busy.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetH = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: SizedBox(
        height: sheetH,
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(Tokens.sp5, Tokens.sp3, Tokens.sp5, Tokens.sp4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // sheet-head（index.html:565-568）
              Row(
                children: [
                  const Text('我的食物库',
                      style: TextStyle(
                          fontSize: Tokens.textLg,
                          fontWeight: FontWeight.w800,
                          color: Tokens.ink)),
                  const Spacer(),
                  Semantics(
                    label: '关闭', // :567 aria-label 逐字
                    button: true,
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
              // segmented（:569-572 双钮，文案逐字）
              Row(
                children: [
                  Expanded(
                    child: LibSegButton(
                      key: libSegKey('custom'),
                      label: '我的自定义',
                      selected: _tab == 'custom',
                      onTap: () => _selectTab('custom'),
                    ),
                  ),
                  const SizedBox(width: Tokens.sp2),
                  Expanded(
                    child: LibSegButton(
                      key: libSegKey('builtin'),
                      label: '内置常菜',
                      selected: _tab == 'builtin',
                      onTap: () => _selectTab('builtin'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.sp2),
              // sub 行（仅成功取数后在场；失败/在途保留上一成功值 ≙ H5）
              if (_sub != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.sp2),
                  child: Text(_sub!,
                      key: libSubKey,
                      style: const TextStyle(
                          fontSize: Tokens.textXs, color: Tokens.ink3)),
                ),
              Expanded(child: _body()),
              // 层底常驻「＋ 添加自定义食物」（index.html:574 #lib-add：在
              // #lib-list 之外，双 tab/加载/失败态均在；文案逐字，
              // btn-primary btn-block ≙ FilledButton 拉伸 + margin-top sp3）
              const SizedBox(height: Tokens.sp3),
              FilledButton(
                key: libAddKey,
                // ≙ js/app.js:1347 closeFoodLib() → openCustomFoodSheet(true)
                // 关层带 true 回执，由 openFoodLibSheet 接续开表单
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('＋ 添加自定义食物'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// #lib-list 区四态（:1305 加载中 / :1319 空态 / :1325 行族 / :1337 失败+重试）
  Widget _body() {
    if (_loading) {
      return const Center(
          child: Text('加载中…',
              style: TextStyle(fontSize: Tokens.textMd, color: Tokens.ink3)));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⚠️',
                style: TextStyle(fontSize: Tokens.textXl)), // :1338 art
            Text('加载失败：$_error', // :1338 逐字
                style: const TextStyle(
                    fontSize: Tokens.textMd, color: Tokens.ink2)),
            const SizedBox(height: Tokens.sp3),
            FilledButton.tonal(
              key: libRetryKey,
              onPressed: _render, // #lib-retry → renderLibList（:1355）
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_tab == 'custom') {
      if (_custom.isEmpty) {
        return const Center( // :1320 空态逐字
            child: Text('还没有自定义食物\n点下方按钮添加你的常吃菜',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: Tokens.textMd, color: Tokens.ink3)));
      }
      return ListView.separated(
        itemCount: _custom.length,
        separatorBuilder: (_, _) => const SizedBox(height: Tokens.sp2),
        itemBuilder: (_, i) => _customRow(_custom[i]),
      );
    }
    final list = _builtinCache ?? const <dynamic>[];
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: Tokens.sp2),
      itemBuilder: (_, i) => _builtinRow(list[i]),
    );
  }

  /// 自定义行（:1310-1319）：thumb + 名/meta/餐次钮组 + 删除钮
  Widget _customRow(dynamic f) {
    final m = (f as Map).cast<String, dynamic>();
    final id = '${m['id']}';
    final grams = m['grams'] is num ? m['grams'] as num : 0;
    final unit = m['unit'] == 'ml' ? 'ml' : 'g'; // cfUnitOf :1186
    String n(String k) => m[k] is num ? jsNumText(m[k] as num) : '${m[k] ?? 0}';
    // :1315 meta 模板（grams falsy 去前缀；数字 JS 串形）
    final meta =
        '${grams != 0 ? '${jsNumText(grams)}$unit · ' : ''}${n('kcal')} kcal · 蛋白 ${n('protein')}g / 碳水 ${n('carb')}g / 脂肪 ${n('fat')}g';
    final kind = cfMealKind(m['meals']);
    return Container(
      padding: const EdgeInsets.all(Tokens.sp3),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
        border: Border.all(color: Tokens.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FoodThumb(
              source: '${m['image'] ?? ''}',
              emoji: '${m['emoji'] ?? ''}'.isEmpty ? '🍽️' : '${m['emoji']}'),
          const SizedBox(width: Tokens.sp3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m['name'] as String? ?? '', // :1314
                    style: const TextStyle(
                        fontSize: Tokens.textMd,
                        fontWeight: FontWeight.w700,
                        color: Tokens.ink)),
                const SizedBox(height: Tokens.sp1),
                Text(meta, // :1315
                    style: const TextStyle(
                        fontSize: Tokens.textXs, color: Tokens.ink3)),
                const SizedBox(height: Tokens.sp2),
                Row(
                  children: [
                    for (final k in const ['breakfast', 'lunch', 'snack'])
                      Padding(
                        padding: const EdgeInsets.only(right: Tokens.sp2),
                        child: LibMealChip(
                          key: libMealKey(id, k),
                          label: _kindLabels[k]!,
                          selected: kind == k,
                          disabled: _busy.contains('meal:$id:$k'),
                          onTap: () => _setMeal(id, k),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Tokens.sp2),
          TextButton( // :1318 「删除」danger 钮
            key: libDelKey(id),
            onPressed:
                _busy.contains('del:$id') ? null : () => _delete(id),
            child: const Text('删除',
                style: TextStyle(
                    color: Tokens.danger, fontSize: Tokens.textSm)),
          ),
        ],
      ),
    );
  }

  /// 内置行（:1325-1335）：thumb + 名/meta + 移除⇄恢复钮；hidden 行置灰
  Widget _builtinRow(dynamic f) {
    final m = (f as Map).cast<String, dynamic>();
    final id = '${m['id']}';
    final hidden = m['hidden'] == true;
    final kcal = m['kcal'] is num ? jsNumText(m['kcal'] as num) : '${m['kcal']}';
    return Opacity(
      opacity: hidden ? 0.45 : 1, // .lib-item-removed 置灰观感（R4 表达）
      child: Container(
        padding: const EdgeInsets.all(Tokens.sp3),
        decoration: BoxDecoration(
          color: Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          border: Border.all(color: Tokens.line),
        ),
        child: Row(
          children: [
            FoodThumb(
                source: '${m['image'] ?? ''}',
                emoji: '${m['emoji'] ?? ''}'.isEmpty ? '🍽️' : '${m['emoji']}'),
            const SizedBox(width: Tokens.sp3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m['name'] as String? ?? '', // :1329
                      style: const TextStyle(
                          fontSize: Tokens.textMd,
                          fontWeight: FontWeight.w700,
                          color: Tokens.ink)),
                  const SizedBox(height: Tokens.sp1),
                  Text('${m['meta'] ?? ''} · $kcal kcal', // :1330
                      style: const TextStyle(
                          fontSize: Tokens.textXs, color: Tokens.ink3)),
                ],
              ),
            ),
            const SizedBox(width: Tokens.sp2),
            TextButton( // :1333 钮文案 移除⇄恢复 二态
              key: libTogKey(id),
              onPressed: _busy.contains('tog:$id')
                  ? null
                  : () => _toggleBuiltin(m),
              child: Text(hidden ? '恢复' : '移除',
                  style: TextStyle(
                      color: hidden ? Tokens.primaryDeep : Tokens.danger,
                      fontSize: Tokens.textSm)),
            ),
          ],
        ),
      ),
    );
  }
}

/// seg 双钮之一（R4 视觉；文案 index.html:570-571 逐字）
@visibleForTesting
class LibSegButton extends StatelessWidget {
  const LibSegButton({
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Tokens.sp2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Tokens.primarySoft : Tokens.surfaceSoft,
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: Tokens.textSm,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? Tokens.primaryDeep : Tokens.ink3)),
      ),
    );
  }
}

/// 餐次归类钮（:1316 cf-meal-chip；active=该档高亮）
@visibleForTesting
class LibMealChip extends StatelessWidget {
  const LibMealChip({
    super.key,
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap, // mealChip.disabled 语义
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Tokens.sp2, vertical: Tokens.sp1),
          decoration: BoxDecoration(
            color: selected ? Tokens.primary : Tokens.surfaceSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: Tokens.textXs,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? Colors.white : Tokens.ink3)),
        ),
      ),
    );
  }
}
