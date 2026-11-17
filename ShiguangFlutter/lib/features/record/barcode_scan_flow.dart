// M16：商品条码扫描入口。
// 流程：相机扫到 8–14 位合法条码（校验位通过）→ 调 /foods/barcode →
// 命中就开「按克加」份量层；未收录则引导手动添加并保留条码绑定。
// 相机不可用/拒绝权限时，页面内仍可手动输入条码，功能不完全依赖相机。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../home/home_controller.dart' show healthApiProvider;
import 'barcode_util.dart';
import 'custom_food_sheet.dart';
import 'label_scan_flow.dart';
import 'portion_sheet.dart';

class BarcodeLookupResult {
  const BarcodeLookupResult({
    required this.barcode,
    this.food,
    this.notFound = false,
    this.message,
  });

  final String barcode;
  final Map<String, dynamic>? food;
  final bool notFound;
  final String? message;
}

Future<void> openBarcodeScanFlow(
  BuildContext context,
  WidgetRef ref, {
  required String date,
  required String meal,
  void Function()? onSaved,
}) async {
  final result = await Navigator.of(context).push<BarcodeLookupResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const BarcodeScanPage(),
    ),
  );
  if (result == null || !context.mounted) return;

  final food = result.food;
  if (food != null) {
    // 没有 per100 的行进份量层会被当成 0 kcal/0 宏量，等于静默记了个空条目。
    if (food['per100'] is! Map) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('这条商品缺少营养数据，请手动添加或编辑')),
        );
      return;
    }
    await showPortionSheet(context, food: food, date: date, meal: meal);
    return;
  }

  if (result.notFound) {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('条码未收录'),
        content: Text(
          '${result.barcode}\n\n商品库里没有这条记录。可以拍包装背面的营养成分表，'
          '自动填入名称与每 100g 营养；也可以手动填写。保存后会记住条码，'
          '下次扫同一件商品直接命中。',
          style: const TextStyle(fontSize: Tokens.textSm),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('manual'),
            child: const Text('手动添加'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('label'),
            child: const Text('拍营养表'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'manual') {
      await openCustomFoodSheet(
        context,
        date: date,
        meal: meal,
        initialBarcode: result.barcode,
        onSaved: onSaved ?? () {},
      );
    } else if (choice == 'label') {
      await openNutritionLabelScan(
        context,
        ref,
        barcode: result.barcode,
        date: date,
        meal: meal,
        onSaved: onSaved,
      );
    }
    return;
  }

  final message = result.message ?? '条码查询失败';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class BarcodeScanPage extends ConsumerStatefulWidget {
  const BarcodeScanPage({super.key});

  @override
  ConsumerState<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends ConsumerState<BarcodeScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookup(String raw) async {
    final code = raw.trim();
    if (!isValidBarcode(code)) return;
    if (_busy) return;
    setState(() => _busy = true);
    await _controller.stop();
    try {
      final r = await ref.read(healthApiProvider).lookupBarcode(code);
      if (!mounted) return;
      final found = r['found'] == true && r['food'] is Map;
      final food = found
          ? Map<String, dynamic>.from(r['food'] as Map)
          : null;
      Navigator.of(context).pop(
        BarcodeLookupResult(
          barcode: code,
          food: food,
          notFound: !found && r['ok'] == true,
          message: food == null ? (r['message'] as String?) : null,
        ),
      );
    } on ApiException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('网络异常，请重试');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    _controller.start();
  }

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('手动输入条码'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(14),
          ],
          decoration: const InputDecoration(hintText: '8–14 位商品条码'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('查询'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty || !mounted) return;
    if (!isValidBarcode(code)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('条码校验位不正确，请核对后重输')));
      return;
    }
    await _lookup(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('扫商品条码'),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, _) => IconButton(
              tooltip: '手电筒',
              onPressed: state.torchState == TorchState.unavailable
                  ? null
                  : () => _controller.toggleTorch(),
              icon: Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on_rounded
                    : Icons.flash_off_rounded,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_busy) return;
              for (final barcode in capture.barcodes) {
                final raw = barcode.rawValue;
                if (raw == null) continue;
                if (isValidBarcode(raw)) {
                  _lookup(raw);
                  return;
                }
              }
            },
          ),
          // 取景框
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_busy)
            const ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('查询商品中…',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Column(
              children: [
                const Text(
                  '把商品包装上的条码放进取景框',
                  style: TextStyle(color: Colors.white70, fontSize: Tokens.textSm),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _manualEntry,
                  icon: const Icon(Icons.keyboard_rounded),
                  label: const Text('手动输入条码'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
