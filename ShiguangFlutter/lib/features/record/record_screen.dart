// ShiguangFlutter/lib/features/record/record_screen.dart
// 记录页（M2 Task 9）：餐次分段 + 该餐次已记列表（长按删除，有确认）+「＋ 记一笔」。
// 行为权威源 js/app.js：页面标题「饮食记录」（index.html:142）、餐次 tab 文案
// （index.html:281-284 + MEAL_NAMES）、空餐组「未记录 / ＋ 加一份」（517-538）、
// 全天空态（521-528）、删除确认文案（557-560）、toast（571/584）、
// 底部「＋ 记一笔」（index.html:248）。
// 数据：复用 home_controller 的 recordsProvider（同 family 不重建，与首页共享缓存）。
// 与 H5 差异：H5 记录页纵向平铺四个餐次分组；M2 按任务简报改为顶部餐次分段，
// 只呈现当前餐次已记列表。H5 的 ✕ 按钮删除改为长按+确认（简报二选一取有确认者）。
// M7-T6：顶部 7 天日期行（≙ js/app.js renderDateRow :498-516）+ 列表日期源由
// todayProvider 改 plateDateProvider（≙ H5 全局 state.date，与首页五卡共享）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../data/swr_cache.dart' show swrCacheProvider;
import '../../domain/constants.dart';
import '../../domain/dates.dart' show localIso;
import '../home/home_controller.dart' show plateDateProvider;
import '../common/food_thumb.dart';
import '../common/pressable.dart' show PressableScale;
import 'record_controller.dart';
import 'search_sheet.dart';

class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key, this.initialMeal});

  /// 测试注入口：null 时按 H5 defaultMeal 逻辑取当前小时档（js/app.js:603-609）。
  final String? initialMeal;

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  late String _meal =
      widget.initialMeal ?? defaultMealAt(DateTime.now().hour);

  static String _n(num v) => '${v.round()}';

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openSearch(String date) =>
      showSearchSheet(context, date: date, meal: _meal);

  /// 删除：长按记录行 → 确认弹层（文案逐字抄 js/app.js:559）→ deleteFoodRecord。
  /// 与 H5 差异：不做乐观删除（Riverpod 下 invalidate 重取即最终一致，
  /// 且避免失败回滚的双份簿记）。
  Future<void> _confirmDelete(String date, Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Tokens.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusLg)),
        title: const Text('确认删除',
            style: TextStyle(
                fontSize: Tokens.textLg,
                fontWeight: FontWeight.w700,
                color: Tokens.ink)),
        content: const Text('删除后无法恢复，确定要删除这条记录吗？',
            style: TextStyle(fontSize: Tokens.textMd, color: Tokens.ink2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消',
                style: TextStyle(color: Tokens.ink3, fontSize: Tokens.textMd)),
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
    if (ok != true || !mounted) return;
    final id = '${r['id']}';
    try {
      await ref.read(recordControllerProvider).deleteRecord(date, id);
      _toast('已删除记录');
    } on ApiException catch (e) {
      _toast('删除失败：${e.message}');
    } catch (_) {
      _toast('删除失败：网络异常');
    }
  }

  @override
  Widget build(BuildContext context) {
    // M7-T6：日期源=共享 plateDateProvider（≙ H5 全局 state.date，js/app.js:512
    // chip 点击直写 + :514 renderPlateDate 联动首页餐盘）。此前 M2 固定
    // todayProvider（每天只见当天），本任务改为可与首页互翻的 7 天行。
    final date = ref.watch(plateDateProvider);
    final records = ref.watch(recordsProvider(date));

    // 自带 Scaffold：SnackBars（H5 toast 位）在本屏内呈现，不依赖 Shell
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Tokens.sp4, Tokens.sp4, Tokens.sp4, Tokens.sp3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('饮食记录',
                  style: TextStyle(
                      fontSize: Tokens.textXl,
                      fontWeight: FontWeight.w800,
                      color: Tokens.ink)),
              const SizedBox(height: Tokens.sp3),
              _dateRow(date),
              const SizedBox(height: Tokens.sp3),
              _mealSeg(),
              const SizedBox(height: Tokens.sp3),
              Expanded(
                child: records.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _errorCard(date, e),
                  data: (list) => _mealSection(date, list),
                ),
              ),
              const SizedBox(height: Tokens.sp3),
              // 底部记一笔入口（H5 index.html:248「＋ 记一笔」）
              FilledButton(
                onPressed: () => _openSearch(date),
                child: const Text('＋ 记一笔'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部 7 天日期行 ≙ js/app.js renderDateRow（:498-516）：
  /// 7 chip = 今天往前 7 天（今-6..今，:501-503），末位（i==6）文案「今天」，
  /// 其余「M/D」不补零（:506 实读——非 dateLabelOf 的「M月D日」形态）；
  /// 点击置共享日期源（≙ :512 `state.date = chip.dataset.date`），
  /// recordsProvider(date) 等 family 随 watch 自动重取（≙ :515 并行拉取）；
  /// 无未来闸——行内本无未来日（H5 :510-512 同款，不判）。
  /// 版式 ≙ screens.css:395-396：flex 等分 7 列 + 8px gap（R4：单行不滚，
  /// 与 H5 同形；chip 视觉 ≙ components.css:52-61 .chip/.chip.active）。
  Widget _dateRow(String selected) {
    final now = DateTime.now();
    final chips = <Widget>[];
    for (var i = 0; i < 7; i++) {
      final d = DateTime(now.year, now.month, now.day - (6 - i));
      final iso = localIso(d);
      chips.add(Expanded(
        child: Padding(
          // gap 8px（--sp-2），末位不挂尾隙
          padding: EdgeInsets.only(right: i == 6 ? 0 : Tokens.sp2),
          child: _dateChip(iso, i == 6 ? '今天' : '${d.month}/${d.day}',
              iso == selected),
        ),
      ));
    }
    return Row(children: chips);
  }

  Widget _dateChip(String iso, String label, bool active) {
    return GestureDetector(
      // ≙ :509-512 点击置 state.date（plateDateProvider ≙ T1 共享日期源；
      // 首页五卡/餐盘胶囊同容器同 provider，天然联动）
      onTap: () => ref.read(plateDateProvider.notifier).state = iso,
      child: AnimatedContainer(
        key: ValueKey('date-chip-$iso'),
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9), // .chip padding 9px 0
        decoration: BoxDecoration(
          color: active ? Tokens.primary : Tokens.surface,
          borderRadius: BorderRadius.circular(999), // --radius-full
          border: Border.all(
              color: active ? Colors.transparent : Tokens.hairline),
          boxShadow: active
              // .chip.active box-shadow: 0 4px 14px -4px var(--primary-glow)
              ? const [
                  BoxShadow(
                      color: Tokens.primaryGlow,
                      offset: Offset(0, 4),
                      blurRadius: 14,
                      spreadRadius: -4)
                ]
              : const [
                  // .chip 常态微影 0 1px 2px rgba(28,36,24,.03)
                  BoxShadow(
                      color: Color(0x081C2418),
                      offset: Offset(0, 1),
                      blurRadius: 2)
                ],
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Tokens.textSm,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? Colors.white : Tokens.ink2, // --on-primary
            )),
      ),
    );
  }

  /// 顶部餐次分段：早/午/晚/零食（MEAL_ORDER 顺序，文案 MEAL_NAMES 逐字）
  Widget _mealSeg() {
    return Container(
      padding: const EdgeInsets.all(Tokens.sp1),
      decoration: BoxDecoration(
        color: Tokens.surfaceSoft,
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Row(
        children: [
          for (final meal in mealOrder)
            Expanded(
              // M9-T6（B1 接线）：餐次 chip 的 tap 改由 PressableScale 承载
              // （外层唯一手势=按下 0.975 回弹，内层 AnimatedContainer 纯
              // 视觉），不嵌套双识别器（控制器裁定④：原 GestureDetector
              // 即单一 onTap，原位替换，零结构改造面）。
              child: PressableScale(
                key: ValueKey('meal-tab-$meal'),
                onTap: () => setState(() => _meal = meal),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(vertical: Tokens.sp2),
                  decoration: BoxDecoration(
                    color: _meal == meal ? Tokens.surface : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(Tokens.radiusSm),
                    boxShadow:
                        _meal == meal ? Tokens.shadowCard : null,
                  ),
                  child: Text(
                    mealNames[meal]!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: Tokens.textSm,
                      fontWeight:
                          _meal == meal ? FontWeight.w700 : FontWeight.w400,
                      color: _meal == meal ? Tokens.primaryDeep : Tokens.ink3,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorCard(String date, Object? error) {
    final msg = error is ApiException ? error.message : '加载失败，请检查网络后重试';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(msg,
              style: const TextStyle(
                  color: Tokens.danger, fontSize: Tokens.textMd)),
          const SizedBox(height: Tokens.sp2),
          TextButton(
            // M9-T2：重试先删 SWR 键再 invalidate（强制走网络，不吃播种）
            onPressed: () {
              ref.read(swrCacheProvider).invalidate('records.$date');
              ref.invalidate(recordsProvider(date));
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _mealSection(String date, List<Map<String, dynamic>> list) {
    // 全天无记录：统一空态（js/app.js:521-528）
    if (list.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🍽️', style: TextStyle(fontSize: Tokens.textXl)),
            SizedBox(height: Tokens.sp2),
            Text('这一天还没有记录',
                style: TextStyle(
                    fontSize: Tokens.textLg,
                    fontWeight: FontWeight.w700,
                    color: Tokens.ink)),
            SizedBox(height: Tokens.sp1),
            Text('点下方「记一笔」记下第一餐，开始追踪热量',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3)),
          ],
        ),
      );
    }
    final mealList =
        list.where((r) => r['meal'] == _meal).toList(growable: false);
    final sum = mealList.fold<num>(
        0, (a, r) => a + ((r['kcal'] as num?) ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.sp1),
          child: Row(
            children: [
              Text('${mealNames[_meal]}已记',
                  style: const TextStyle(
                      fontSize: Tokens.textSm,
                      fontWeight: FontWeight.w700,
                      color: Tokens.ink2)),
              const Spacer(),
              // T8（终审 Minor M2）：合计与行内 _n() 同口径取整——per100 记录的
              // kcal 可能是小数，直插 '$sum' 会显 "232.0 kcal"；H5 侧
              // js/app.js 合计走 Math.round 显示口径。
              Text('${_n(sum)} kcal',
                  style: const TextStyle(
                      fontSize: Tokens.textSm,
                      fontWeight: FontWeight.w700,
                      color: Tokens.primaryDeep)),
            ],
          ),
        ),
        const SizedBox(height: Tokens.sp2),
        Expanded(
          child: mealList.isEmpty
              ? _emptyMeal(date)
              : ListView.separated(
                  itemCount: mealList.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: Tokens.sp2),
                  itemBuilder: (_, i) => _recordTile(date, mealList[i]),
                ),
        ),
      ],
    );
  }

  /// 当前餐次为空（全天有记录）：细提示 +「＋ 加一份」直接为该餐记一笔
  /// （js/app.js:532-538）
  Widget _emptyMeal(String date) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('未记录',
              style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3)),
          const SizedBox(height: Tokens.sp2),
          OutlinedButton(
            onPressed: () => _openSearch(date),
            child: const Text('＋ 加一份'),
          ),
        ],
      ),
    );
  }

  /// 已记列表行：缩略 / 名 / portion / kcal；长按触发删除确认
  Widget _recordTile(String date, Map<String, dynamic> r) {
    final kcal = (r['kcal'] as num?) ?? 0;
    return GestureDetector(
      key: ValueKey('record-${r['id']}'),
      onLongPress: () => _confirmDelete(date, r),
      child: Container(
        padding: const EdgeInsets.all(Tokens.sp3),
        decoration: BoxDecoration(
          color: Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          boxShadow: Tokens.shadowCard,
        ),
        child: Row(
          children: [
            // 缩略图位（js/app.js:546 r.image ? img : r.emoji）：M5-T4 FoodThumb。
            // M2 移植时此行漏了 emoji 缩略列，本任务补齐并对齐带图记录。
            FoodThumb(
              source: (r['image'] as String?) ?? '',
              emoji: (r['emoji'] as String?) ?? '🍽️',
            ),
            const SizedBox(width: Tokens.sp3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r['name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: Tokens.textMd,
                        fontWeight: FontWeight.w700,
                        color: Tokens.ink),
                  ),
                  const SizedBox(height: Tokens.sp1),
                  Text(
                    '${r['portion'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: Tokens.textSm, color: Tokens.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Tokens.sp2),
            Text(
              '${_n(kcal)} kcal',
              style: const TextStyle(
                  fontSize: Tokens.textSm,
                  fontWeight: FontWeight.w700,
                  color: Tokens.ink2),
            ),
          ],
        ),
      ),
    );
  }
}
