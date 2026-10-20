// ShiguangFlutter/test/data/image_pick_test.dart
// M13-T4：选图管道参数化用尺。扫码链需要 512 长边/q75（识别精度优先），
// 头像与自定义食物链维持 256 长边/q82/280000 字符默认值不变。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/common/image_pick.dart';

void main() {
  test('classifyPicked 支持自定义上限；默认上限不变', () {
    final s = 'data:image/jpeg;base64,${'A' * 100}';
    expect(classifyPicked(s, maxChars: 50).failure,
        ImagePickFailure.tooLargeEncoded);
    expect(classifyPicked(s).failure, isNull);
    expect(classifyPicked(null).dataUrl, isNull);
  });

  test('扫码参数常量：比默认大、质量更低', () {
    expect(kScanImageMaxDim, 512);
    expect(kScanImageQuality, 75);
    expect(kScanImageMaxDim, greaterThan(256));
    expect(kScanImageQuality, lessThan(82));
  });
}
