// ShiguangFlutter/lib/features/record/record_screen.dart
// 记录页（M2 Task 9）：餐次分段 + 该餐次已记列表（长按删除，有确认）+「＋ 记一笔」。
// 行为权威源 js/app.js：页面标题「饮食记录」（index.html:142）、餐次 tab 文案
// （index.html:281-284 + MEAL_NAMES）、空餐组「未记录 / ＋ 加一份」（517-538）、
// 全天空态（521-528）、删除确认文案（557-560）、toast（571/584）、
// 底部「＋ 记一笔」（index.html:248）。
// 数据：复用 home_controller 的 recordsProvider（同 family 不重建，与首页共享缓存）。
// 与 H5 差异：H5 记录页纵向平铺四个餐次分组；M2 按任务简报改为顶部餐次分段，
// 只呈现当前餐次已记列表。H5 的 ✕ 按钮删除改为长按+确认（简报二选一取有确认者）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/constants.dart';
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
    final date = ref.watch(todayProvider);
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
              child: GestureDetector(
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
            onPressed: () => ref.invalidate(recordsProvider(date)),
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
              Text('$sum kcal',
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

  /// 已记列表行：名 / portion / kcal；长按触发删除确认
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
