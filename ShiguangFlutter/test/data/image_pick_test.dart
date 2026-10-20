// ShiguangFlutter/test/data/image_pick_test.dart
// M13-T4：选图管道参数化用尺。扫码链需要 512 长边/q75（识别精度优先），
// 头像与自定义食物链维持 256 长边/q82/280000 字符默认值不变。
// M13 收口：并入原 test/common/image_pick_test.dart 的默认边界用例（等值放行）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/common/data_url.dart';
import 'package:shiguang_flutter/features/common/image_pick.dart';

void main() {
  test('classifyPicked 支持自定义上限；默认上限等值放行、超一字符即拒', () {
    final s = 'data:image/jpeg;base64,${'A' * 100}';
    expect(classifyPicked(s, maxChars: 50).failure,
        ImagePickFailure.tooLargeEncoded);
    expect(classifyPicked(s).failure, isNull);
    expect(classifyPicked(null).dataUrl, isNull);
    // 边界：恰好等于上限必须放行（K-Max 口径同 H5 `> 280000` 才拒）
    expect(classifyPicked('a' * kMaxDataUrlChars).failure, isNull);
    expect(classifyPicked('a' * (kMaxDataUrlChars + 1)).failure,
        ImagePickFailure.tooLargeEncoded);
  });

  test('dataUrlTooLarge 支持自定义上限（单一权威，不再两处手写比较）', () {
    expect(dataUrlTooLarge('a' * 10, maxChars: 10), isFalse);
    expect(dataUrlTooLarge('a' * 11, maxChars: 10), isTrue);
    expect(dataUrlTooLarge('a' * kMaxDataUrlChars), isFalse);
    expect(dataUrlTooLarge('a' * (kMaxDataUrlChars + 1)), isTrue);
  });

  test('扫码参数常量：比默认大、质量更低', () {
    expect(kScanImageMaxDim, 512);
    expect(kScanImageQuality, 75);
    expect(kScanImageMaxDim, greaterThan(256));
    expect(kScanImageQuality, lessThan(82));
  });
}
