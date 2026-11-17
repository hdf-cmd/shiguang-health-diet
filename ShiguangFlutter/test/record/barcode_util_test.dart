// M16：客户端条码校验与云端 barcode.js 同算法（tests/barcode.test.js 对侧）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/record/barcode_util.dart';

void main() {
  test('合法 EAN-13 / EAN-8 / UPC-A 通过', () {
    expect(isValidBarcode('4006381333931'), isTrue);
    expect(isValidBarcode('96385074'), isTrue);
    expect(isValidBarcode('036000291452'), isTrue);
  });

  test('校验位错 / 长度不对 / 非数字拒绝', () {
    expect(isValidBarcode('4006381333932'), isFalse);
    expect(isValidBarcode('1234567'), isFalse);
    expect(isValidBarcode('123456789012345'), isFalse);
    expect(isValidBarcode('40063813339a1'), isFalse);
    expect(isValidBarcode(''), isFalse);
  });

  test('isBarcodeShape 只判 8–14 位数字，不校验校验位', () {
    expect(isBarcodeShape('4006381333932'), isTrue);
    expect(isBarcodeShape('12345678'), isTrue);
    expect(isBarcodeShape('1234567'), isFalse);
    expect(isBarcodeShape('40063813339a1'), isFalse);
  });
}
