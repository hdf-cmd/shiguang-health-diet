// M16：拍包装营养成分表 → 视觉模型读每 100g/ml → 预填自定义食物表单。
// 条码负责「是哪件商品」，营养表负责「具体数值」；保存后绑定条码，下次扫码直接命中。
// 拍摄体验：拍摄指引 → 拍后预览重拍 → 低置信度再次确认，避免模糊图直接入库。
import 'dart:convert';

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
  while (true) {
    if (!context.mounted) return;
    final image = await _pickLabelImage(context);
    if (image == null || !context.mounted) return;

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
            image,
            provider: provider,
            hint: initialName,
          );
      navigator.pop(); // 关闭「读取营养表中」
      if (!context.mounted) return;

      if (r['ok'] != true || r['per100'] is! Map) {
        final retry = await _askRetry(
          context,
          (r['message'] as String?) ?? '没读出来，请重拍或手动填写',
        );
        if (retry == true) continue;
        return;
      }

      final confidence = '${r['confidence'] ?? 'low'}';
      final lowConfidence = r['verify'] == true || confidence != 'high';
      if (lowConfidence) {
        final retry = await _askLowConfidence(context, confidence);
        if (retry == true) continue;
        if (!context.mounted) return;
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
      return;
    } on ApiException catch (e) {
      navigator.pop();
      if (!context.mounted) return;
      final retry = await _askRetry(context, e.message);
      if (retry == true) continue;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (_) {
      navigator.pop();
      if (!context.mounted) return;
      final retry = await _askRetry(context, '识别失败，请重试');
      if (retry == true) continue;
      return;
    }
  }
}

/// 拍摄指引 → 拍照/相册 → 压缩 → 预览确认。返回 null 表示用户取消。
Future<String?> _pickLabelImage(BuildContext context) async {
  while (true) {
    if (!context.mounted) return null;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.sp4, Tokens.sp2, Tokens.sp4, Tokens.sp1,
              ),
              child: Text(
                '让营养成分表占满画面，保持手机稳定，避开反光和阴影。'
                '模糊照片会读错数值。',
                style: TextStyle(
                  fontSize: Tokens.textSm,
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('拍照'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('从相册选'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('取消'),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return null;

    var picked = await pickCompressedImageDataUrl(
      source,
      maxDim: 1600,
      quality: 85,
      maxChars: 600000,
    );
    // 高分辨率压缩后仍超限时回退到 1200/q82，避免直接失败。
    if (picked.failure == ImagePickFailure.tooLargeEncoded) {
      picked = await pickCompressedImageDataUrl(
        source,
        maxDim: 1200,
        quality: 82,
        maxChars: 600000,
      );
    }
    if (picked.dataUrl == null) {
      if (!context.mounted) return null;
      if (picked.failure == ImagePickFailure.tooLargeEncoded) {
        _toast(context, '图片仍过大，请靠近一点重拍');
      } else if (picked.failure == ImagePickFailure.readFailed) {
        _toast(context, '图片处理失败');
      } else {
        return null; // 用户取消相机/相册
      }
      continue;
    }
    if (!context.mounted) return null;

    final use = await _confirmPreview(context, picked.dataUrl!);
    if (use == true) return picked.dataUrl;
    if (use == null) return null;
    // use == false：重拍，回到来源选择
  }
}

Future<bool?> _confirmPreview(BuildContext context, String dataUrl) {
  final bytes = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(Tokens.sp5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(Tokens.sp2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Tokens.radiusSm),
                  child: InteractiveViewer(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.sp4),
              child: Text(
                '确认营养表文字清晰可辨。模糊、反光或倾斜会导致识别数值偏差。',
                style: TextStyle(
                  fontSize: Tokens.textSm,
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.sp4, Tokens.sp2, Tokens.sp4, Tokens.sp3,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('重拍'),
                  ),
                  const SizedBox(width: Tokens.sp2),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('使用这张'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool?> _askRetry(BuildContext context, String message) =>
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('没读出来'),
        content: Text(message, style: const TextStyle(fontSize: Tokens.textSm)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('重拍'),
          ),
        ],
      ),
    );

Future<bool?> _askLowConfidence(BuildContext context, String confidence) =>
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('识别把握不大'),
        content: Text(
          '模型给出的置信度是「${confidence == 'medium' ? '中等' : '较低'}」，'
          '照片可能模糊或反光。建议重拍，或对照包装核对后再保存。',
          style: const TextStyle(fontSize: Tokens.textSm),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续核对'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('重拍'),
          ),
        ],
      ),
    );

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
