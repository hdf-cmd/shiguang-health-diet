import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/common/image_pick.dart';
import 'package:shiguang_flutter/features/common/data_url.dart';

void main() {
  test('编码超限 → tooLargeEncoded；正常串直通（toast 文案归 UI 层）', () {
    expect(classifyPicked('a' * 100), (dataUrl: 'a' * 100, failure: null));
    expect(classifyPicked('a' * (kMaxDataUrlChars + 1)).failure,
        ImagePickFailure.tooLargeEncoded);
    expect(classifyPicked(null), (dataUrl: null, failure: null)); // 取消
  });
}
