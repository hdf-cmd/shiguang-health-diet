// ShiguangFlutter/lib/features/common/image_pick.dart
// 选图+压缩管道（T5 头像 / T7 自定义食物共用）。压缩不在 Dart 侧重编码：
// image_picker 在 Android 原生侧按 maxWidth/maxHeight=256 + imageQuality=82
// 降采样重编码（H5 compressAvatar 的 256 长边/q0.82 等价参数，js/app.js:1091-1097）。
// 行为差异登记：H5 的「原图 >5MB 先拒」闸（:1107）在原生重编码后不可见，
// 由「编码后 >280000 字符拒」兜底——超大原图压不进 280K 时文案同 H5「图片仍过大，请换一张」。
// M13-T4：尺寸/质量/字符上限参数化。不传参仍是 256/q82/280000（头像与自定义
// 食物零行为变化）；扫码链显式传 kScanImageMaxDim/kScanImageQuality。
import 'package:image_picker/image_picker.dart';

import 'data_url.dart';

enum ImagePickFailure { tooLargeEncoded, readFailed }

typedef PickedImageData = ({String? dataUrl, ImagePickFailure? failure});

/// 扫码识图参数：长边 512、q75——比头像/自定义食物更清晰，压低体积靠质量。
const int kScanImageMaxDim = 512;
const int kScanImageQuality = 75;

/// 纯映射（可单测）：null=取消静默；超限→tooLargeEncoded。
/// [maxChars] 默认沿用 H5 头像/自定义食物口径，扫码链可另传。
PickedImageData classifyPicked(String? dataUrl,
    {int maxChars = kMaxDataUrlChars}) {
  if (dataUrl == null) return (dataUrl: null, failure: null);
  if (dataUrl.length > maxChars) {
    return (dataUrl: null, failure: ImagePickFailure.tooLargeEncoded);
  }
  return (dataUrl: dataUrl, failure: null);
}

/// 拉起系统选择器（camera/gallery 由调用方传），返回压缩后 dataURL。
/// 默认值即原行为；扫码链传 `maxDim: kScanImageMaxDim, quality: kScanImageQuality`。
Future<PickedImageData> pickCompressedImageDataUrl(
  ImageSource source, {
  int maxDim = 256,
  int quality = 82,
  int maxChars = kMaxDataUrlChars,
}) async {
  final XFile? file;
  try {
    file = await ImagePicker().pickImage(
        source: source,
        maxWidth: maxDim.toDouble(),
        maxHeight: maxDim.toDouble(),
        imageQuality: quality);
  } catch (_) {
    return (dataUrl: null, failure: ImagePickFailure.readFailed);
  }
  if (file == null) return (dataUrl: null, failure: null); // 取消
  try {
    return classifyPicked(dataUrlOf(await file.readAsBytes()),
        maxChars: maxChars);
  } catch (_) {
    return (dataUrl: null, failure: ImagePickFailure.readFailed);
  }
}
