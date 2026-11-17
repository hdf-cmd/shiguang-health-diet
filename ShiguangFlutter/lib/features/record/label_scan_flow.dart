// M16：拍包装营养成分表 → 视觉模型读每 100g/ml → 预填自定义食物表单。
// 条码负责「是哪件商品」，营养表负责「具体数值」；保存后绑定条码，下次扫码直接命中。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../../app/theme.dart';
import '../../data/ai_provider_store.dart' show aiProviderStoreProvider;
import '../../data/api_client.dart' show ApiException;
import '../common/image_pick.dart';
import 'custom_food_sheet.dart';
import 'record_controller.dart';

Future<void> openNutritionLabelScan(
  BuildContext context,
  WidgetRef ref, {
  required String barcode,
  required String date,
  required String meal,
  String? initialName,
  void Function()? onSaved,
}) async {
  final picked = await pickCompressedImageDataUrl(
    ImageSource.camera,
    maxDim: 1200,
    quality: 82,
    maxChars: 600000,
  );
  if (picked.dataUrl == null) {
    if (!context.mounted) return;
    if (picked.failure == ImagePickFailure.tooLargeEncoded) {
      _toast(context, '图片仍过大，请靠近一点重拍');
    } else if (picked.failure == ImagePickFailure.readFailed) {
      _toast(context, '图片处理失败');
    }
    return;
  }
  if (!context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _LabelLoadingDialog(),
  );

  try {
    final provider = await ref.read(aiProviderStoreProvider).load();
    final r = await ref.read(healthApiProvider).scanNutritionLabel(
          picked.dataUrl!,
          provider: provider,
          hint: initialName,
        );
    navigator.pop(); // 关闭「读取营养表中」
    if (!context.mounted) return;
    if (r['ok'] != true || r['per100'] is! Map) {
      messenger.showSnackBar(
        SnackBar(content: Text((r['message'] as String?) ?? '没读出来，请重拍或手动填写')),
      );
      return;
    }
    final per100 = Map<String, dynamic>.from(r['per100'] as Map);
    final name = '${r['name'] ?? ''}'.trim();
    final servingGrams = (r['servingGrams'] as num?)?.toDouble();
    final unit = r['unit'] == 'ml' ? 'ml' : 'g';
    await openCustomFoodSheet(
      context,
      date: date,
      meal: meal,
      initialName: name.isNotEmpty ? name : initialName,
      initialBarcode: barcode,
      initialGrams: servingGrams,
      initialPer100: per100,
      initialUnit: unit,
      onSaved: onSaved ?? () {},
    );
  } on ApiException catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('识别失败，请重试')));
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

class _LabelLoadingDialog extends StatelessWidget {
  const _LabelLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.sp5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: Tokens.sp3),
              Text(
                '读取营养表中…',
                style: TextStyle(
                  fontSize: Tokens.textMd,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
