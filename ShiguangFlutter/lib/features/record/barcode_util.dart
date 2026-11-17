// M16：条码校验（客户端镜像 cloudfunctions/api-diet/barcode.js 的算法）。
// 只负责「扫到的这串数字是不是一个合法商品码」，不做任何网络判断。
bool isBarcodeShape(String raw) {
  final s = raw.trim();
  if (s.length < 8 || s.length > 14) return false;
  return RegExp(r'^\d+$').hasMatch(s);
}

/// EAN-8 / UPC-A / EAN-13 / GTIN-14 共用的 Modulo-10 校验位。
bool isValidBarcode(String raw) {
  final s = raw.trim();
  if (!isBarcodeShape(s)) return false;
  final digits = s.codeUnits.map((u) => u - 0x30).toList(growable: false);
  var sum = 0;
  for (var i = digits.length - 2, w3 = true; i >= 0; i--, w3 = !w3) {
    sum += digits[i] * (w3 ? 3 : 1);
  }
  return (10 - (sum % 10)) % 10 == digits.last;
}
