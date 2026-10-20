// ShiguangFlutter/test/record/scan_image_pick_test.dart
// M13 收口：钉「扫码链真的把 512/q75 传进压缩管道」——只断言常量值的旧用例
// 在常量改回 256 时仍然全绿，测不出漏接线。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:shiguang_flutter/features/common/image_pick.dart';
import 'package:shiguang_flutter/features/record/food_scan_sheet.dart';

class _RecordingCompressor extends ImageCompressor {
  ImageSource? source;
  int? dim;
  int? quality;
  int? maxChars;

  @override
  Future<PickedImageData> pick(
    ImageSource source, {
    int maxDim = 256,
    int quality = 82,
    int maxChars = 280000,
  }) async {
    this.source = source;
    dim = maxDim;
    this.quality = quality;
    this.maxChars = maxChars;
    return (dataUrl: 'data:image/jpeg;base64,AAA', failure: null);
  }
}

void main() {
  test('scanImagePickProvider 显式传 512/q75 给压缩管道（漏接线即红）', () async {
    final fake = _RecordingCompressor();
    final c = ProviderContainer(overrides: [
      imageCompressorProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);

    final picked = await c.read(scanImagePickProvider)(ImageSource.camera);

    expect(fake.source, ImageSource.camera);
    expect(fake.dim, kScanImageMaxDim);
    expect(fake.quality, kScanImageQuality);
    expect(fake.dim, 512);
    expect(fake.quality, 75);
    expect(picked.dataUrl, isNotNull);
    expect(picked.failure, isNull);
  });
}
