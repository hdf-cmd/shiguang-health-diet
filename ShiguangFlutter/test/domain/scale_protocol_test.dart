// ShiguangFlutter/test/domain/scale_protocol_test.dart
// B1 体脂秤协议纯 Dart 移植的测试向量：按 ScaleSync.kt:212-289 规则手构的"真机形状"帧
// + 两个已知实测值（0x51 实时 66.66kg、0x54 旧存档 13.05kg）。权威源：ScaleSync.kt。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/scale_protocol.dart';

/// 按 Kotlin 规则手构一条 0x51 实时帧：
/// kg → flags（le32 落在 b[2..5]，kgRaw=(le32&0x3FFFF)/1000，bit31=locked）。
List<int> liveFrame(double kg, {bool locked = false}) {
  final flags = ((kg * 1000).round() & 0x3FFFF) | (locked ? 0x80000000 : 0);
  final f = List<int>.filled(20, 0);
  f[0] = 0xAF;
  f[1] = 0x45;
  f[2] = flags & 0xFF;
  f[3] = (flags >> 8) & 0xFF;
  f[4] = (flags >> 16) & 0xFF;
  f[5] = (flags >> 24) & 0xFF; // le32
  f[18] = 0x51;
  var sum = 0;
  for (var i = 2; i <= 18; i++) {
    sum += f[i];
  }
  f[19] = sum & 0x1F;
  return f;
}

/// 一条 0x54 旧存档帧（实测秤推 13.05kg），形状与 liveFrame 相同，仅线型不同。
List<int> oldStoreFrame(double kg) {
  final f = liveFrame(kg);
  f[18] = 0x54;
  var sum = 0;
  for (var i = 2; i <= 18; i++) {
    sum += f[i];
  }
  f[19] = sum & 0x1F;
  return f;
}

void main() {
  group('parseScaleFrame', () {
    test('0x51 正常帧：kgRaw 与 locked 正确（净字节序=le32）', () {
      final sf = parseScaleFrame(liveFrame(66.66))!;
      expect(sf.kgRaw, 66.66);
      expect(sf.locked, isFalse);
    });

    test('locked 位：bit31 置位能被识别', () {
      final sf = parseScaleFrame(liveFrame(70.0, locked: true))!;
      expect(sf.kgRaw, 70.0);
      expect(sf.locked, isTrue);
    });

    test('0x54 旧存档帧一律忽略（返回 null）', () {
      expect(parseScaleFrame(oldStoreFrame(13.05)), isNull);
    });

    test('坏 crc → null', () {
      final f = liveFrame(66.66);
      f[19] = (f[19] + 1) & 0x1F; // 破坏校验
      expect(parseScaleFrame(f), isNull);
    });

    test('坏帧头 → null', () {
      final f = liveFrame(66.66);
      f[0] = 0x00;
      expect(parseScaleFrame(f), isNull);
    });

    test('长度≠20 → null', () {
      expect(parseScaleFrame(List<int>.filled(19, 0)), isNull);
      expect(parseScaleFrame(List<int>.filled(21, 0)), isNull);
    });
  });

  group('filterReading', () {
    test('范围过滤：<2.0 与 >300.0 丢弃', () {
      expect(filterReading(ScaleFrame(kgRaw: 1.9, locked: false)), isNull);
      expect(filterReading(ScaleFrame(kgRaw: 300.1, locked: false)), isNull);
    });

    test('round 两位小数：66.666 → 66.67', () {
      final e = filterReading(ScaleFrame(kgRaw: 66.666, locked: false))!;
      expect(e.kg, 66.67);
    });

    test('locked 直通：changed=true', () {
      final e = filterReading(ScaleFrame(kgRaw: 66.66, locked: true), lastKg: 66.66)!;
      expect(e.locked, isTrue);
      expect(e.changed, isTrue);
    });

    test('非 locked 同值：changed=false', () {
      final e = filterReading(ScaleFrame(kgRaw: 66.66, locked: false), lastKg: 66.66)!;
      expect(e.changed, isFalse);
    });

    test('非 locked 新值：changed=true 且 kg 已 round', () {
      final e = filterReading(ScaleFrame(kgRaw: 66.684, locked: false), lastKg: 66.66)!;
      expect(e.kg, 66.68);
      expect(e.changed, isTrue);
    });

    test('非 locked round 后与 lastKg 相等 → changed=false（去重）', () {
      final e = filterReading(ScaleFrame(kgRaw: 66.664, locked: false), lastKg: 66.66)!;
      expect(e.kg, 66.66);
      expect(e.changed, isFalse);
    });
  });

  group('handshakeFrames / buildFrame / time4LE', () {
    // 简报给的 `d8 01 0b 6a`(=0x6A0B01D8=1779106264) 与 1780000000 不符（简报算术笔误）。
    // Kotlin time4 是机械的秒→小端 4 字节，故 1780000000(=0x6A18A500) 的小端为 00 a5 18 6a。
    // 权威源为 ScaleSync.kt，此处按真实小端断言并在报告登记该偏离。
    test('time4LE(1780000000) = 0x6A18A500 的小端 00 a5 18 6a', () {
      expect(time4LE(1780000000), <int>[0x00, 0xA5, 0x18, 0x6A]);
    });

    test('handshakeFrames 返回 3 帧', () {
      expect(handshakeFrames(1780000000), hasLength(3));
    });

    test('校时帧：cmd=0x16 wireType=0x5F body 前 4 字节小端 + 0x20 + 10 个 0', () {
      final frames = handshakeFrames(1780000000);
      final t = frames[0];
      expect(t.length, kScaleFrameLen);
      expect(t[0], 0xAF);
      expect(t[1], 0x45);
      expect(t[2], 0x16);
      expect(t[18], 0x5F);
      expect(t.sublist(3, 7), <int>[0x00, 0xA5, 0x18, 0x6A]);
      expect(t[7], 0x20);
      expect(t.sublist(8, 18), List<int>.filled(10, 0));
      expect(t[19], frameCrc(t));
    });

    test('两条 SYNC 帧：cmd=0x04 wireType=0x62，body 照抄 SYNC_BODY_1/2', () {
      final frames = handshakeFrames(1780000000);
      for (final i in <int>[1, 2]) {
        final s = frames[i];
        expect(s[2], 0x04);
        expect(s[18], 0x62);
        expect(s[19], frameCrc(s));
      }
      expect(frames[1].sublist(3, 18), kSyncBody1);
      expect(frames[2].sublist(3, 18), kSyncBody2);
    });

    test('buildFrame 空 body 不越界', () {
      final f = buildFrame(0x16, 0x5F, <int>[]);
      expect(f.length, kScaleFrameLen);
      expect(f[2], 0x16);
      expect(f[18], 0x5F);
      expect(f[19], frameCrc(f));
    });

    test('buildFrame 满 body（15 字节）落 f[3..17] 且不越界', () {
      final body = List<int>.generate(15, (i) => i + 1);
      final f = buildFrame(0x04, 0x62, body);
      expect(f.length, kScaleFrameLen);
      expect(f.sublist(3, 18), body);
      expect(f[19], frameCrc(f));
    });
  });
}
