// ShiguangFlutter/lib/data/mi_crypto.dart
// 小米云 STS 传输加密（与 mi_fitness_data_bridge 的 Python 实现逐字节对齐，
// 测试向量见 test/data/mi_crypto_test.dart）。
// 分层铁律：本文件不得 import flutter / dio —— 纯函数，可离线单测。
//
// 协议要点（对照 mi_fitness_cloud.py:117-158）：
// - rc4：key 先跑 1024 字节丢弃，再做流加密；
// - signedNonce = SHA256(ssecurity + nonce)；
// - signature = base64(SHA1("method&path&data=..[&rc4_hash__=..]" + "&" + b64(signedNonce)))。
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// RC4 流加密（小米协议要求先丢弃 1024 字节密钥流）。
Uint8List rc4Crypt(List<int> key, List<int> payload) {
  final s = List<int>.generate(256, (i) => i);
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key[i % key.length]) % 256;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
  }
  var a = 0;
  j = 0;
  int nextByte() {
    a = (a + 1) % 256;
    j = (j + s[a]) % 256;
    final t = s[a];
    s[a] = s[j];
    s[j] = t;
    return s[(s[a] + s[j]) % 256];
  }

  for (var k = 0; k < 1024; k++) {
    nextByte();
  }
  final out = Uint8List(payload.length);
  for (var i = 0; i < payload.length; i++) {
    out[i] = payload[i] ^ nextByte();
  }
  return out;
}

/// nonce = 8 字节随机 + 4 字节大端「当前分钟数」。
Uint8List genNonce([Random? random, DateTime? now]) {
  final rnd = random ?? Random.secure();
  final out = Uint8List(12);
  for (var i = 0; i < 8; i++) {
    out[i] = rnd.nextInt(256);
  }
  final minutes = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 60000;
  out[8] = (minutes >> 24) & 0xFF;
  out[9] = (minutes >> 16) & 0xFF;
  out[10] = (minutes >> 8) & 0xFF;
  out[11] = minutes & 0xFF;
  return out;
}

/// signedNonce = SHA256(ssecurity ‖ nonce)
Uint8List genSignedNonce(List<int> ssecurity, List<int> nonce) =>
    Uint8List.fromList(
        sha256.convert(<int>[...ssecurity, ...nonce]).bytes);

/// 签名串：method&path&data=..[&rc4_hash__=..]&`b64(signedNonce)`。
/// [values] 必须包含 'data'，可能包含 'rc4_hash__'（顺序固定，不遍历 map）。
String genSignature(
    String method, String path, Map<String, String> values, List<int> signedNonce) {
  var base = '$method&$path&data=${values['data']}';
  final rc4Hash = values['rc4_hash__'];
  if (rc4Hash != null) {
    base += '&rc4_hash__=$rc4Hash';
  }
  base += '&${base64.encode(signedNonce)}';
  return base64.encode(sha1.convert(utf8.encode(base)).bytes);
}
