// ShiguangFlutter/test/data/mi_crypto_test.dart
// 加密层与 Python 参考实现逐字节对齐（向量由 mi_fitness_cloud.py 实算生成）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/mi_crypto.dart';

List<int> hexToBytes(String hex) => Uint8List.fromList(
    [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

void main() {
  final ssecurity = utf8.encode('0123456789abcdef');
  final nonce = hexToBytes('101010101010101000bc614e');
  const payload = '{"start_time":1,"end_time":2,"limit":50}';
  const path = '/app/v1/data/get_sport_records_by_time';

  late Uint8List signedNonce;
  setUpAll(() => signedNonce = genSignedNonce(ssecurity, nonce));

  test('genSignedNonce = SHA256(ssecurity+nonce)', () {
    expect(base64.encode(signedNonce),
        'tBB6V7l0ChRriEGd8sy3iAhoKYni7HSXpnRuwQFIqUg=');
  });

  test('rc4Crypt 丢弃 1024 字节后与参考实现一致', () {
    expect(base64.encode(rc4Crypt(signedNonce, utf8.encode(payload))),
        'JCS1o3DuLbovgCrCLPbqiEdKnQY/F9QiTJ7sWtfCvC1VTkwXRblMMg==');
  });

  test('genSignature：未加密表单只含 data', () {
    final sig =
        genSignature('POST', path, {'data': payload}, signedNonce);
    expect(sig, 'oeGSKLvtWsrbio1pJKoksrP+KKQ=');
  });

  test('genSignature：加密表单带 rc4_hash__，且遇签名后字段不受影响', () {
    final enc = <String, String>{
      'data': base64.encode(rc4Crypt(signedNonce, utf8.encode(payload))),
      'rc4_hash__': base64.encode(
          rc4Crypt(signedNonce, utf8.encode('oeGSKLvtWsrbio1pJKoksrP+KKQ='))),
    };
    expect(genSignature('POST', path, enc, signedNonce),
        '0K26IlweXN+2Gy2pIDkXvnaW9dA=');
  });

  test('genNonce：8 字节随机 + 4 字节大端分钟数', () {
    final n = genNonce(null, DateTime.fromMillisecondsSinceEpoch(12345678 * 60000));
    expect(n.length, 12);
    final minutes = (n[8] << 24) | (n[9] << 16) | (n[10] << 8) | n[11];
    expect(minutes, 12345678);
  });

  test('rc4Crypt 可逆', () {
    final key = utf8.encode('key-123');
    final plain = utf8.encode('hello-xiaomi');
    expect(rc4Crypt(key, rc4Crypt(key, plain)), plain);
  });
}
