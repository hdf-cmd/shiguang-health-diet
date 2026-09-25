import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/common/data_url.dart';

void main() {
  test('PNG magic → image/png；其余 → image/jpeg（H5 png 保透明口径）', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2]);
    expect(dataUrlOf(png), startsWith('data:image/png;base64,'));
    expect(dataUrlOf(jpg), startsWith('data:image/jpeg;base64,'));
    expect(dataUrlOf(Uint8List(0)), startsWith('data:image/jpeg;base64,')); // 短/非PNG一律jpeg
  });
  test('dataUrlOf base64 与 dart:convert 逐字一致', () {
    final b = Uint8List.fromList([1, 2, 3, 4]);
    expect(dataUrlOf(b), 'data:image/jpeg;base64,${base64Encode(b)}');
  });
  test('280000 字符闸边界', () {
    expect(kMaxDataUrlChars, 280000);
    final s = 'x' * kMaxDataUrlChars;
    expect(dataUrlTooLarge(s), isFalse);
    expect(dataUrlTooLarge('$s.'), isTrue);
  });
}
