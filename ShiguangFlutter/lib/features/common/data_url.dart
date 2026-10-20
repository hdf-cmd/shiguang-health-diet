// ShiguangFlutter/lib/features/common/data_url.dart
// 图片 bytes → dataURL 字符串。对齐 H5 compressAvatar 产物形态（js/app.js:1099
// png 保 png、其余 jpeg）与两道尺寸闸的「编码后」那道（:1108 dataUrl.length>280000）。
import 'dart:convert';

/// H5 头像/自定义食物图 dataURL 字符上限（js/app.js:1108 逐字数字）。
const int kMaxDataUrlChars = 280000;

bool dataUrlTooLarge(String dataUrl, {int maxChars = kMaxDataUrlChars}) =>
    dataUrl.length > maxChars;

/// PNG magic（89 50 4E 47）嗅探定 MIME，其余一律 jpeg——H5 同口径。
String dataUrlOf(List<int> bytes) {
  final isPng = bytes.length >= 4 &&
      bytes[0] == 0x89 && bytes[1] == 0x50 &&
      bytes[2] == 0x4E && bytes[3] == 0x47;
  final mime = isPng ? 'image/png' : 'image/jpeg';
  return 'data:$mime;base64,${base64Encode(bytes)}';
}
