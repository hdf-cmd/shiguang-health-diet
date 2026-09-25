// ShiguangFlutter/lib/features/common/image_pick.dart
// 选图+压缩管道（T5 头像 / T7 自定义食物共用）。压缩不在 Dart 侧重编码：
// image_picker 在 Android 原生侧按 maxWidth/maxHeight=256 + imageQuality=82
// 降采样重编码（H5 compressAvatar 的 256 长边/q0.82 等价参数，js/app.js:1091-1097）。
// 行为差异登记：H5 的「原图 >5MB 先拒」闸（:1107）在原生重编码后不可见，
// 由「编码后 >280000 字符拒」兜底——超大原图压不进 280K 时文案同 H5「图片仍过大，请换一张」。
import 'package:image_picker/image_picker.dart';

import 'data_url.dart';

enum ImagePickFailure { tooLargeEncoded, readFailed }

typedef PickedImageData = ({String? dataUrl, ImagePickFailure? failure});

/// 纯映射（可单测）：null=取消静默；超限→tooLargeEncoded。
PickedImageData classifyPicked(String? dataUrl) {
  if (dataUrl == null) return (dataUrl: null, failure: null);
  if (dataUrlTooLarge(dataUrl)) {
    return (dataUrl: null, failure: ImagePickFailure.tooLargeEncoded);
  }
  return (dataUrl: dataUrl, failure: null);
}

/// 拉起系统选择器（camera/gallery 由调用方传），返回压缩后 dataURL。
Future<PickedImageData> pickCompressedImageDataUrl(ImageSource source) async {
  final XFile? file;
  try {
    file = await ImagePicker().pickImage(
        source: source, maxWidth: 256, maxHeight: 256, imageQuality: 82);
  } catch (_) {
    return (dataUrl: null, failure: ImagePickFailure.readFailed);
  }
  if (file == null) return (dataUrl: null, failure: null); // 取消
  try {
    return classifyPicked(dataUrlOf(await file.readAsBytes()));
  } catch (_) {
    return (dataUrl: null, failure: ImagePickFailure.readFailed);
  }
}
