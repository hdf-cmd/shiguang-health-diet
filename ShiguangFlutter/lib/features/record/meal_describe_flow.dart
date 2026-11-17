// M16：「描述一餐」入口。
// 链路：一句话 → /ai/meal-parse（模型只抽食物名与份量）→ 云端逐条命中
// 内置/自定义库 → 本页复核 → 批量记入。
// 没命中的行可以「按菜名估算」走 /ai/food-estimate，并明确标成 AI 估算；
// 也可以取消勾选跳过。估算值永远不冒充库内数据。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/ai_provider_store.dart' show aiProviderStoreProvider;
import '../../data/api_client.dart' show ApiException;
import '../../domain/meal_describe.dart'
    show formatMealAmount, initialMealAmount, mealMatchesOf;
import '../../domain/models.dart' show Per100;
import '../../domain/portion.dart' show portionMacros;
import '../common/sheet.dart' show showShiguangSheet;
import 'record_controller.dart';

Future<void> openMealDescribeFlow(
  BuildContext context,
  WidgetRef ref, {
  required String date,
  required String meal,
}) async {
  final parsed = await showShiguangSheet<Map<String, dynamic>>(
    context,
    title: '描述一餐',
    child: _DescribeInputSheet(meal: meal),
  );
  if (parsed == null || !context.mounted) return;

  final rawItems = (parsed['items'] as List?) ?? const [];
  final items = rawItems
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
  if (items.isEmpty) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('没从这句话里找到食物')));
    return;
  }

  await showShiguangSheet<void>(
    context,
    title: '确认这一餐',
    child: _MealReviewSheet(items: items, date: date, meal: meal),
  );
}

class _DescribeInputSheet extends ConsumerStatefulWidget {
  const _DescribeInputSheet({required this.meal});

  final String meal;

  @override
  ConsumerState<_DescribeInputSheet> createState() =>
      _DescribeInputSheetState();
}

class _DescribeInputSheetState extends ConsumerState<_DescribeInputSheet> {
  final TextEditingController _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _text.text.trim();
    if (text.length < 2) {
      setState(() => _error = '多写一点，比如「一碗米饭、两个鸡蛋」');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final provider = await ref.read(aiProviderStoreProvider).load();
      final r = await ref.read(healthApiProvider).parseMealText(
            text,
            provider: provider,
            meal: widget.meal,
          );
      if (!mounted) return;
      if (r['ok'] != true) {
        setState(() {
          _busy = false;
          _error = (r['message'] as String?) ?? '识别失败，换个说法再试';
        });
        return;
      }
      final items = (r['items'] as List?) ?? const [];
      if (items.isEmpty) {
        setState(() {
          _busy = false;
          _error = '没从这句话里找到食物';
        });
        return;
      }
      Navigator.of(context).pop(r);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '网络异常，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: Tokens.sp5,
        right: Tokens.sp5,
        top: Tokens.sp2,
        bottom: Tokens.sp4 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '用一句话写清吃了什么，比如：一碗米饭、两个鸡蛋、一份清炒青菜',
            style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3),
          ),
          const SizedBox(height: Tokens.sp2),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            maxLength: 200,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: '例如：早餐两个鸡蛋一杯牛奶',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Tokens.sp1),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: Tokens.textSm,
                color: Tokens.danger,
              ),
            ),
          ],
          const SizedBox(height: Tokens.sp3),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? '解析中…' : '解析这一餐'),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow {
  _ReviewRow(this.item) {
    match = item['match'] is Map
        ? Map<String, dynamic>.from(item['match'] as Map)
        : null;
    matches = mealMatchesOf(item, match);
    if (matches.isNotEmpty) match = matches.first;
    amount = TextEditingController(
      text: formatMealAmount(initialMealAmount(item, match)),
    );
  }

  final Map<String, dynamic> item;
  Map<String, dynamic>? match;
  late List<Map<String, dynamic>> matches;
  late final TextEditingController amount;
  bool selected = true;
  bool estimated = false;
  bool estimating = false;
  String? error;

  bool get hasPer100 => match != null && match!['per100'] is Map;

  String get name =>
      '${match?['name'] ?? item['query'] ?? ''}'.trim();

  String get unitLabel => hasPer100
      ? (match!['unit'] == 'ml' ? 'ml' : 'g')
      : '份';
}

class _MealReviewSheet extends ConsumerStatefulWidget {
  const _MealReviewSheet({
    required this.items,
    required this.date,
    required this.meal,
  });

  final List<Map<String, dynamic>> items;
  final String date;
  final String meal;

  @override
  ConsumerState<_MealReviewSheet> createState() => _MealReviewSheetState();
}

class _MealReviewSheetState extends ConsumerState<_MealReviewSheet> {
  late final List<_ReviewRow> _rows =
      widget.items.map(_ReviewRow.new).toList(growable: false);
  bool _busy = false;

  @override
  void dispose() {
    for (final row in _rows) {
      row.amount.dispose();
    }
    super.dispose();
  }

  double _amountOf(_ReviewRow row) =>
      double.tryParse(row.amount.text.trim()) ?? 0;

  num _kcalOf(_ReviewRow row) {
    final m = row.match;
    final amount = _amountOf(row);
    if (m == null || amount <= 0) return 0;
    final per100 = m['per100'];
    if (per100 is Map) {
      final p = Per100.fromMap(Map<String, Object?>.from(per100));
      return portionMacros(p, amount).kcal;
    }
    final baseKcal = (m['kcal'] as num?) ?? 0;
    return (baseKcal * amount).round();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _estimate(_ReviewRow row) async {
    if (row.estimating) return;
    final query = '${row.item['query'] ?? ''}'.trim();
    if (query.isEmpty) return;
    setState(() {
      row.estimating = true;
      row.error = null;
    });
    try {
      final provider = await ref.read(aiProviderStoreProvider).load();
      final r = await ref.read(healthApiProvider).estimateFood(
            query,
            provider: provider,
          );
      if (!mounted) return;
      final per100 = r['per100'];
      if (r['ok'] != true || per100 is! Map) {
        setState(() {
          row.estimating = false;
          row.error = (r['message'] as String?) ?? '估算失败，请手动添加';
        });
        return;
      }
      final dish = '${r['dish'] ?? ''}'.trim();
      setState(() {
        row.match = <String, dynamic>{
          'name': dish.isEmpty ? query : dish,
          'per100': Map<String, dynamic>.from(per100),
          'baseG': 100,
          'unit': 'g',
          'emoji': '🍽️',
          'image': '',
          'meta': 'AI 估算 · 仅按常见做法推算，请核对',
        };
        row.estimated = true;
        row.estimating = false;
        row.matches = [row.match!];
        row.amount.text = formatMealAmount(
          initialMealAmount(row.item, row.match),
        );
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        row.estimating = false;
        row.error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        row.estimating = false;
        row.error = '网络异常，请重试';
      });
    }
  }

  Future<void> _pickMatch(_ReviewRow row) async {
    if (_busy || row.matches.length <= 1) return;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < row.matches.length; i++)
              ListTile(
                title: Text('${row.matches[i]['name'] ?? ''}'),
                subtitle: Text('${row.matches[i]['meta'] ?? ''}'),
                trailing: identical(row.match, row.matches[i])
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(i),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      row.match = row.matches[chosen];
      row.estimated = false;
      row.error = null;
      row.amount.text = formatMealAmount(
        initialMealAmount(row.item, row.match),
      );
    });
  }

  Future<void> _submit() async {
    // 未命中的行如果还勾着，先拦下来：静默跳过等于把用户写的东西扔掉。
    final unresolved = _rows
        .where((r) => r.selected && r.match == null)
        .toList(growable: false);
    if (unresolved.isNotEmpty) {
      _toast('有未命中的项：先按菜名估算，或取消勾选');
      return;
    }
    // 选中但份量为 0 的行同样不能静默丢，否则用户以为记了、实际没记。
    final zeroAmount = _rows
        .where((r) => r.selected && r.match != null && _amountOf(r) <= 0)
        .toList(growable: false);
    if (zeroAmount.isNotEmpty) {
      _toast('有选中项份量为 0，请填写份量或取消勾选');
      return;
    }
    final picks = _rows
        .where((r) => r.selected && r.match != null && _amountOf(r) > 0)
        .toList(growable: false);
    if (picks.isEmpty) {
      _toast('至少选一项并填写份量');
      return;
    }
    final controller = ref.read(recordControllerProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    var done = 0;
    for (var i = 0; i < picks.length; i++) {
      // 用户关掉复核层后停止后续写入：已经发出去的保持，未发的不再补记。
      if (!mounted) return;
      final row = picks[i];
      final m = row.match!;
      final amount = _amountOf(row);
      final name = row.name;
      if (name.isEmpty) continue;
      final Map<String, dynamic> body;
      final per100 = m['per100'];
      if (per100 is Map) {
        final p = Per100.fromMap(Map<String, Object?>.from(per100));
        final r = portionMacros(p, amount.round());
        final unit = m['unit'] == 'ml' ? 'ml' : 'g';
        body = <String, dynamic>{
          'date': widget.date,
          'meal': widget.meal,
          'name': name,
          'portion': '${amount.round()}$unit',
          'kcal': r.kcal,
          'emoji': m['emoji'] ?? '🍽️',
          'image': m['image'] ?? '',
          'protein': r.protein,
          'carb': r.carb,
          'fat': r.fat,
        };
      } else {
        final baseKcal = (m['kcal'] as num?) ?? 0;
        body = <String, dynamic>{
          'date': widget.date,
          'meal': widget.meal,
          'name': name,
          'portion': '${formatMealAmount(amount)}份',
          'kcal': (baseKcal * amount).round(),
          'emoji': m['emoji'] ?? '🍽️',
          'image': m['image'] ?? '',
          'protein': ((m['protein'] as num?) ?? 0) * amount,
          'carb': ((m['carb'] as num?) ?? 0) * amount,
          'fat': ((m['fat'] as num?) ?? 0) * amount,
        };
      }
      try {
        final ok = await controller.addRecord(
          widget.date,
          body,
          pendingKey: 'describe:${widget.date}:$i:$name',
        );
        if (ok) done++;
        if (!mounted) return;
      } catch (e) {
        final reason = e is ApiException ? e.message : '网络异常';
        if (!mounted) return;
        setState(() => _busy = false);
        _toast('第 ${i + 1} 项「$name」记入失败：$reason');
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (done > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('已记入 $done 项 · 可继续添加')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.sp5,
        Tokens.sp2,
        Tokens.sp5,
        Tokens.sp4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '核对食物与份量。没命中的项可以按菜名估算，估算值会标注出来。',
            style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3),
          ),
          const SizedBox(height: Tokens.sp2),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: Tokens.sp2),
              itemBuilder: (_, i) => _rowTile(_rows[i]),
            ),
          ),
          const SizedBox(height: Tokens.sp3),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? '记入中…' : '记入选中的项'),
          ),
        ],
      ),
    );
  }

  Widget _rowTile(_ReviewRow row) {
    final m = row.match;
    return Container(
      padding: const EdgeInsets.all(Tokens.sp3),
      decoration: BoxDecoration(
        color: Tokens.surface2,
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
        border: Border.all(color: Tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                value: row.selected,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => row.selected = v == true),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: Tokens.textMd,
                              fontWeight: FontWeight.w700,
                              color: Tokens.ink,
                            ),
                          ),
                        ),
                        if (row.estimated) ...[
                          const SizedBox(width: Tokens.sp1),
                          const _Tag(text: 'AI 估算'),
                        ],
                      ],
                    ),
                    const SizedBox(height: Tokens.sp1),
                    Text(
                      m == null
                          ? '没找到「${row.item['query'] ?? ''}」，可估算或跳过'
                          : '${m['meta'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: Tokens.textXs,
                        color: Tokens.ink3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (m != null)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.sp2),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: row.amount,
                      enabled: !_busy,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        suffixText: row.unitLabel,
                      ),
                    ),
                  ),
                  const SizedBox(width: Tokens.sp3),
                  Text(
                    '≈ ${_kcalOf(row).round()} kcal',
                    style: const TextStyle(
                      fontSize: Tokens.textSm,
                      fontWeight: FontWeight.w700,
                      color: Tokens.ink2,
                    ),
                  ),
                  if (row.matches.length > 1) ...[
                    const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : () => _pickMatch(row),
                      child: const Text('换一个'),
                    ),
                  ],
                ],
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy || row.estimating
                    ? null
                    : () => _estimate(row),
                child: Text(row.estimating ? '估算中…' : '按菜名估算'),
              ),
            ),
          if (row.error != null)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.sp1),
              child: Text(
                row.error!,
                style: const TextStyle(
                  fontSize: Tokens.textXs,
                  color: Tokens.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Tokens.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: Tokens.textXs,
          fontWeight: FontWeight.w700,
          color: Tokens.primaryDeep,
        ),
      ),
    );
  }
}
