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
// R4 差异登记（修复轮 1 更新；M7 终审 I1 勘正）：#lib-add「＋ 添加自定义食物」
// （index.html:574，层底常驻、双 tab/加载/失败态均在；点击 ≙ js/app.js:1347
// closeFoodLib() → openCustomFoodSheet(true)）本批已补——落点：openFoodLibSheet
// 收到 pop(true) 后关层再开表单（date=plate 日期 ≙ H5 :1244 在途常读全局
// state.date，经 ref 直读 plateDateProvider；meal=默认档 lunch「正餐」）。
// fromLib 形态终裁（M7-T8，结转 T4 Minor③收口）：H5 上游 label/行为不一致——
// :1220 fromLib 主钮文案「存入食物库」，但 :1276 handler 仍走
// saveCustomFood(true)（实际照样记一餐）。**不照搬该文案 bug**：Flutter 维持
// 双钮完整形态（文案与真实行为一致），不实现 fromLib 单钮，详 custom_food_sheet.dart
// 头注「有意背离」登记；本条列入 M7 终审呈报项。toast 走层内 OverlayEntry
// （SheetToast 公共件，M6-T7 F5 定式：SnackBar 会被弹层遮挡并向下层 Scaffold
// 广播双份）。
// M9-T4（perf 批 A1/A2/A3）数据层三改：
// ① 会话缓存——原 `_builtinCache` State 字段（≙ libBuiltinCache :1290，随弹层
//   销毁）删除，双列表数据升为 SwrCache 键 `foods.custom`/`foods.builtin`
//   （spec §1 口径：foods.* 无 TTL，命中即零请求，写路径才删键）→ 重开 0ms 直显；
// ② 并行预取——initState 首帧后 Future.wait 双路（M9-A3），各自命中缓存短路，
//   当前 tab（custom）先渲染不等待另一路；
// ③ 骨架——#lib-list 加载态「加载中…」文本换 3 行 SkeletonBar(height:64)
//   卡形（key lib-skeleton，M9-A2）。
// 注意保留的 H5 语义：自定义 tab 每次 renderLibList 真重取（:1308，钉②观测
// listFoodsCalls 递增——缓存只免「开层首帧等待」，不免切回重取）；内置 tab
// :1322 ||短路由「单层一次」升为「会话一次」；失败支文案与重试链不动。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../data/swr_cache.dart' show swrCacheProvider;
// M11-T1 搜索快照失效入口（同 features/record 的 custom_food_sheet 用法）。
import '../record/record_controller.dart' show invalidateFoodLibrary;
import '../../domain/js_compat.dart' show jsNumText, jsOr;
import '../common/food_thumb.dart';
import '../common/skeleton.dart' show SkeletonBar;
import '../common/sheet.dart' show showShiguangSheet;
import '../common/sheet_toast.dart';
import '../common/stagger.dart' show Stagger;
import '../common/eaten_badge.dart';
import '../home/home_controller.dart' show healthApiProvider, plateDateProvider;
import '../record/custom_food_sheet.dart' show cfMealMap, openCustomFoodSheet;
import '../record/food_freq.dart' show foodFreqProvider;

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

@visibleForTesting
const libSkeletonKey = Key('lib-skeleton'); // M9-A2：加载态骨架区（替「加载中…」）

/// M9-A1：会话缓存键（spec §1 表列：foods.* 无 TTL，写路径才删键）。
/// 写链删键口径同 weight_log_card :145（先删键再刷新）。
@visibleForTesting
const foodsCustomCacheKey = 'foods.custom';

@visibleForTesting
const foodsBuiltinCacheKey = 'foods.builtin';

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
/// （date=plate 日期 ref.read(plateDateProvider) ≙ H5 :1244 在途常读全局
/// state.date——M7 终审 I1：首页/记录页翻到历史日后添加，记餐落所翻之日，
/// 不落今天；meal=默认档正餐，fromLib 单钮形态 T8 终裁不做，见头注与
/// custom_food_sheet.dart「有意背离」登记）。
Future<void> openFoodLibSheet(BuildContext context, WidgetRef ref) async {
  // M9-T8：开层样板收口 showShiguangSheet；bool addRequested 返回语义不变
  // （helper 原样透传 showModalBottomSheet<bool> 的 pop 值）。
  final addRequested = await showShiguangSheet<bool>(
    context,
    title: '我的食物库', // :566 逐字（原标题行现由 helper 承载）
    child: const _FoodLibSheet(),
  );
  if (addRequested == true) {
    if (!context.mounted) return; // 层动画期间入口页可能已销毁
    await openCustomFoodSheet(
      context,
      date: ref.read(plateDateProvider), // ≙ H5 :1244 在途读全局 state.date（≙ plateDateProvider 共享日期源；终审 I1，勘正旧「我的页无选日态⇒todayIso」前提——T1/T6 落地全局日期态后该前提失效）
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
  bool _loading = true; // M9-A1：initState 按缓存命中与否定初值（命中=false）
  String? _error; // ≙ renderLibList catch 支文案（已 ||网络异常 兜底）
  List<dynamic> _custom = const <dynamic>[];

  /// ≙ 原 let libBuiltinCache（:1290）——M9-A1 升为 SwrCache 键
  /// `foods.builtin`（会话级，跨弹层开关存活），本字段仅为当前渲染快照。
  List<dynamic> _builtin = const <dynamic>[];

  /// 在途动作集（≙ 被点钮 disabled=true，:1359/:1371/:1389；失败复位）
  final Set<String> _busy = <String>{};

  /// busy 置位/复位走 setState（M7-T8，T4 Minor②）：H5 :1359 `mealChip.disabled
  /// = true` 是对在体 DOM 节点的即时赋值，点下当帧即灰；此前裸 mutate 只在
  /// 下一场重建（重取/toast 后）生效，在途钮观感未即时置灰。
  void _setBusy(String key, bool on) {
    setState(() => on ? _busy.add(key) : _busy.remove(key));
  }

  /// sub 行：仅成功渲染时更新（:1309/:1324；失败/在途保留上一成功值 ≙ H5
  /// #foodlib-sub 只在成功路径 textContent 赋值）
  String? _sub;

  OverlayEntry? _toastEntry;

  /// lib-add 连点闸（M7-T8，T4 Minor⑤）：pop(true) 后层关闭动画窗口内二次
  /// tap 会再发一次 pop——穿透掉下方路由（H5 无此窗：closeFoodLib 即 display
  /// 切换、:1347 重开表单为幂等函数调用）。最简 bool 守卫，置位后不再回执。
  bool _addPopped = false;

  @override
  void initState() {
    super.initState();
    // M9-A1：开层先吃会话缓存——custom 命中即首帧直显（0ms，无骨架）；
    // miss 保持 _loading=true → 首帧骨架，待 _prefetch 回包覆盖。
    final cache = ref.read(swrCacheProvider);
    final custom = cache.read<List<dynamic>>(foodsCustomCacheKey);
    if (custom != null) {
      _custom = custom;
      _sub = '自定义 ${custom.length} 条 · 点餐次标签可改归类';
      _loading = false;
    }
    final builtin = cache.read<List<dynamic>>(foodsBuiltinCacheKey);
    if (builtin != null) _builtin = builtin;
    // ≙ openFoodLib 尾行 renderLibList()（M9-A3 改为首帧后双路并行预取）
    // M12-④：同时补拉全史计数（幂等；已初始化则零请求），行尾「吃过 N 次」用。
    // 旁路降级同 SearchSheet：初始化失败（无网络/无注入）只是没有徽标，不打断管理弹层。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref
          .read(foodFreqProvider.notifier)
          .ensureLoaded()
          .catchError((Object _) {}));
      _prefetch();
    });
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

  /// M9-A3：首帧完成即双列表并行预取。各路以 SwrCache.read 短路——键在=本会话
  /// 已取过，**不发请求**（foods.* 无 TTL，写路径才失效，spec §1 口径）；
  /// miss=拉+回写。互不等待：当前 tab（custom）回包先渲染，内置后台备妥，
  /// 切 tab 零等待（钉 M9-T4「各拉 1 次」观测面）。
  Future<void> _prefetch() async {
    await Future.wait([
      _fetchTab('custom'),
      _fetchTab('builtin'),
    ]);
  }

  /// 预取单路：命中短路；miss 取数回写并应用。失败：当前 tab → error 支
  /// （≙ 原 renderLibList catch）；非当前 tab → 静默（不留键，切过去再拉）。
  Future<void> _fetchTab(String tab) async {
    final cache = ref.read(swrCacheProvider);
    final key = tab == 'custom' ? foodsCustomCacheKey : foodsBuiltinCacheKey;
    if (cache.read<List<dynamic>>(key) != null) return; // 命中=零请求
    final isCurrent = tab == _tab;
    if (isCurrent) {
      setState(() {
        _loading = true; // initState miss 时已 true；retry 复用本路时复位骨架
        _error = null;
      });
    }
    try {
      final list = tab == 'custom'
          ? await ref.read(healthApiProvider).listCustomFoods()
          : await ref.read(healthApiProvider).getBuiltinFoods();
      cache.write(key, list); // 回写即使本层将销毁（mounted=false）也成立
      if (!mounted || tab != _tab) return;
      setState(() {
        if (tab == 'custom') {
          _custom = list;
          _sub = '自定义 ${list.length} 条 · 点餐次标签可改归类'; // :1309 逐字
        } else {
          _builtin = list;
          _sub = _builtinSub(list); // :1324 逐字
        }
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted && tab == _tab) {
        setState(() {
          _error = jsOr(e.message, '网络异常'); // :1338 e.message||'网络异常'
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && tab == _tab) {
        setState(() {
          _error = '网络异常';
          _loading = false;
        });
      }
    }
  }

  static String _builtinSub(List<dynamic> list) {
    final hiddenCount =
        list.where((f) => f is Map && f['hidden'] == true).length;
    return '内置 ${list.length} 条 · 已移除 $hiddenCount'; // :1324 逐字
  }

  /// renderLibList（:1303-1341 · M9 重写）：tab 切换 / 写后重取 / 失败重试统一
  /// 入口。SWR 渲染序：缓存或既有快照在场→先显后拉（不排骨架）；全无→骨架
  /// 等回包。自定义每次真重取（:1308 语义保留，钉②④⑩b 观测面）；内置命中
  /// 短路零请求（:1322 ||短路升为会话级）。失败仍走 error 支（本入口有用户
  /// 显式动作在场，不静默——≙ 原行为，钉⑩b）。
  Future<void> _render() async {
    final cache = ref.read(swrCacheProvider);
    final isCustom = _tab == 'custom';
    final cached = cache.read<List<dynamic>>(
        isCustom ? foodsCustomCacheKey : foodsBuiltinCacheKey);
    final shown = cached ?? (isCustom ? _custom : _builtin);
    setState(() {
      _error = null;
      if (isCustom) {
        _custom = shown;
        if (cached != null) _sub = '自定义 ${cached.length} 条 · 点餐次标签可改归类';
      } else {
        _builtin = shown;
        if (cached != null) _sub = _builtinSub(cached);
      }
      _loading = shown.isEmpty && cached == null; // 卡形骨架（M9-A2）
    });
    if (!isCustom && cached != null) return; // 内置短路（:1322）：不发请求也不
    // 改态——上面已按缓存渲染（含 toggle 本地翻转后的最新旗标）。
    try {
      final list = isCustom
          ? await ref.read(healthApiProvider).listCustomFoods()
          : await ref.read(healthApiProvider).getBuiltinFoods();
      cache.write(isCustom ? foodsCustomCacheKey : foodsBuiltinCacheKey, list);
      if (!mounted || _tab != (isCustom ? 'custom' : 'builtin')) return;
      setState(() {
        if (isCustom) {
          _custom = list;
          _sub = '自定义 ${list.length} 条 · 点餐次标签可改归类'; // :1309 逐字
        } else {
          _builtin = list;
          _sub = _builtinSub(list);
        }
        _loading = false;
      });
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
    _render(); // 命中短路/先显后拉的判定都在 _render 内（M9）
  }

  /// 归类点按链（:1356-1365）
  Future<void> _setMeal(String id, String kind) async {
    final key = 'meal:$id:$kind';
    if (_busy.contains(key)) return;
    _setBusy(key, true); // mealChip.disabled = true（:1359 即时置灰）
    try {
      await ref
          .read(healthApiProvider)
          .setCustomFoodMeals(id, cfMealMap[kind] ?? const <String>[]);
      if (!mounted) return;
      // M9：写路径「先删键再刷新」（对照 weight_log_card :145 定式）——
      // 否则 :1363 重取的 _render 会先拿旧缓存显出来。
      ref.read(swrCacheProvider).invalidate(foodsCustomCacheKey);
      // M11-T1：搜索快照按餐次各存一份，归类一变即失真 → 整族失效
      invalidateFoodLibrary(ref);
      // :1362 三态文案：breakfast→早餐 / snack→零食 / 其余(lunch 档，含 dinner)→正餐
      _toast('已归到${_kindLabels[kind] ?? '正餐'} · 搜索时只在对应餐次出现');
      await _render(); // :1363 成功后重取
    } on ApiException catch (e) {
      if (mounted) _toast('设置失败：${jsOr(e.message, '网络异常')}'); // :1364
    } catch (_) {
      if (mounted) _toast('设置失败：网络异常');
    } finally {
      if (mounted) _setBusy(key, false); // 失败支 disabled=false 复位（≙ :1364
      // `mealChip.disabled = false`；成功支 H5 随 renderLibList 重建新钮天然
      // 复位，本端同语义：重取后此行按新 _busy 集渲染）
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
    _setBusy(key, true); // del.disabled = true（:1371 即时置灰）
    try {
      await ref.read(healthApiProvider).deleteCustomFood(id);
      if (!mounted) return;
      ref.read(swrCacheProvider).invalidate(foodsCustomCacheKey); // M9 写路径删键
      invalidateFoodLibrary(ref); // M11-T1：删掉的自定义食物不得留在搜索快照里
      _toast('已删除'); // :1374 逐字
      await _render(); // :1375
    } on ApiException catch (e) {
      if (mounted) _toast('删除失败：${jsOr(e.message, '网络异常')}'); // :1376
    } catch (_) {
      if (mounted) _toast('删除失败：网络异常');
    } finally {
      if (mounted) _setBusy(key, false);
    }
  }

  /// 内置移除/恢复（:1379-1396）：全量 ids 提交 → 成功本地翻转 cache 不重取
  Future<void> _toggleBuiltin(Map<dynamic, dynamic> item) async {
    final id = '${item['id']}';
    final key = 'tog:$id';
    if (_busy.contains(key)) return;
    _setBusy(key, true); // tog.disabled = true（:1389 即时置灰）
    try {
      final wasHidden = item['hidden'] == true;
      // :1385-1388：现 hidden 集全量 + 本条摘除/追加（全量替换语义）
      final ids = <String>[
        for (final f in _builtin)
          if (f is Map && f['hidden'] == true) '${f['id']}',
      ];
      if (wasHidden) {
        ids.remove(id);
      } else if (!ids.contains(id)) {
        ids.add(id);
      }
      await ref.read(healthApiProvider).setHiddenFoods(ids);
      if (!mounted) return;
      // M11-T1：hiddenFoods 参与云端搜索过滤（index.js:59），搜索快照必须重取；
      // 下面的「引用别名翻转」只同步 `foods.builtin` 管理列表，覆盖不到快照。
      invalidateFoodLibrary(ref);
      item['hidden'] = !wasHidden; // :1392 本地 cache 翻转（不发重取）——
      // M9：_builtin 与 SwrCache 键 `foods.builtin` 同 List 同 Map 引用，
      // 翻转即会话缓存更新，跨弹层开关一致（foods.builtin 不删键：钉⑥口径）
      // 终审登记：本同步靠「同 List 同 Map 引用别名」成立——若未来取数面
      // （_fetchTab/_render 回写）加防御拷贝，别名断裂，须改为显式删键/回写。
      final hiddenCount = _builtin
          .where((f) => f is Map && f['hidden'] == true)
          .length;
      setState(() => _sub = '内置 ${_builtin.length} 条 · 已移除 $hiddenCount'); // :1393 renderLibList（cache 支零请求）
      _toast(wasHidden
          ? '已恢复「${item['name']}」' // :1394 逐字
          : '已移除「${item['name']}」');
    } on ApiException catch (e) {
      if (mounted) _toast('操作失败：${jsOr(e.message, '网络异常')}'); // :1395
    } catch (_) {
      if (mounted) _toast('操作失败：网络异常');
    } finally {
      if (mounted) _setBusy(key, false); // ≙ :1395 tog.disabled=false（成功支
      // H5 随 :1393 renderLibList 重建复位，本端随本 setState 重绘同效）
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetH = MediaQuery.sizeOf(context).height * 0.72;
    // M12-④：全史计数（观察式——初始化完成/记一笔 +1 后行尾徽标自动刷新）
    final counts = ref.watch(foodFreqProvider);
    // M9-T8：sheet-head 标题「我的食物库」+ ✕（index.html:565-568）与内层
    // SafeArea 由 showShiguangSheet 承载，本地副本删除；0.72h 内容高经 helper
    // Flexible 槽承接（超出 78% 上限时按约束回缩，Expanded 列表自适应）。
    return SizedBox(
      height: sheetH,
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(Tokens.sp5, 0, Tokens.sp5, Tokens.sp4),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Expanded(child: _body(counts)),
              // 层底常驻「＋ 添加自定义食物」（index.html:574 #lib-add：在
              // #lib-list 之外，双 tab/加载/失败态均在；文案逐字，
              // btn-primary btn-block ≙ FilledButton 拉伸 + margin-top sp3）
              const SizedBox(height: Tokens.sp3),
              FilledButton(
                key: libAddKey,
                // ≙ js/app.js:1347 closeFoodLib() → openCustomFoodSheet(true)
                // 关层带 true 回执，由 openFoodLibSheet 接续开表单；
                // _addPopped 闸防关闭动画窗口连点二次 pop（见字段注）。
                onPressed: () {
                  if (_addPopped) return;
                  _addPopped = true;
                  Navigator.of(context).pop(true);
                },
                child: const Text('＋ 添加自定义食物'),
              ),
            ],
          ),
        ),
    );
  }

  /// #lib-list 区四态（M9-A2：:1305 加载中换 3 行卡形骨架 / :1319 空态 /
  /// :1325 行族 / :1337 失败+重试——error 支文案逻辑不动）
  Widget _body(Map<String, int> counts) {
    if (_loading) {
      // 骨架条替「加载中…」文本（钉 M9-T4 首帧观测面：key lib-skeleton）；
      // 纯静态不排持续帧——pumpAndSettle 不死等（SkeletonBar 头注口径）
      return Column(
        key: libSkeletonKey,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: Tokens.sp2),
            const SkeletonBar(height: 64), // 卡形行（≙ 行族 Container 高度量级）
          ],
        ],
      );
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
        // M9-T6（B2 接线）：前 8 行错峰入场（index=行号）。行不包
        // PressableScale——行内删除钮/归类 chip 双手势，外层 Pressable
        // 在手势竞技场必输=假反馈（T5 裁定「无 onTap 不包」延伸）。
        itemBuilder: (_, i) {
          final row = _customRow(_custom[i], counts);
          return i < 8 ? Stagger(index: i, child: row) : row;
        },
      );
    }
    final list = _builtin;
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: Tokens.sp2),
      // M9-T6：同 custom 支——前 8 行 Stagger，行不包 Pressable（裁定同上）。
      itemBuilder: (_, i) {
        final row = _builtinRow(list[i], counts);
        return i < 8 ? Stagger(index: i, child: row) : row;
      },
    );
  }

  /// 自定义行（:1310-1319）：thumb + 名/meta/餐次钮组 + 删除钮
  Widget _customRow(dynamic f, Map<String, int> counts) {
    final m = (f as Map).cast<String, dynamic>();
    final id = '${m['id']}';
    final eaten = counts['${m['name'] ?? ''}'] ?? 0; // M12-④ 全史次数
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
                Row(
                  children: [
                    Flexible(
                      child: Text(m['name'] as String? ?? '', // :1314
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: Tokens.textMd,
                              fontWeight: FontWeight.w700,
                              color: Tokens.ink)),
                    ),
                    if (eaten > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: Tokens.sp2),
                        child: EatenCountBadge(count: eaten),
                      ),
                  ],
                ),
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
  Widget _builtinRow(dynamic f, Map<String, int> counts) {
    final m = (f as Map).cast<String, dynamic>();
    final id = '${m['id']}';
    final eaten = counts['${m['name'] ?? ''}'] ?? 0; // M12-④ 全史次数
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(m['name'] as String? ?? '', // :1329
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: Tokens.textMd,
                                fontWeight: FontWeight.w700,
                                color: Tokens.ink)),
                      ),
                      if (eaten > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: Tokens.sp2),
                          child: EatenCountBadge(count: eaten),
                        ),
                    ],
                  ),
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
