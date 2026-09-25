// ShiguangFlutter/lib/domain/scale_protocol.dart
// 蚂蚁阿福体脂秤 B1（AFU-BH-TZ-B1）协议纯 Dart 移植——只取体重（对齐 Kotlin 侧 v1.3.1 收敛）。
// 逐字移植权威源：HealthyDiet/.../ScaleSync.kt
//   :212-222 parse（帧校验 + 只信 0x51、忽略 0x54 旧存档）
//   :224-237 emit（round 两位、2.0..300.0 过滤、locked 直通、lastKg 去重）
//   :247-256 WEIGHT_MASK / SYNC_BODY_1 / SYNC_BODY_2
//   :258-290 buildFrame / time4 / crc / be32 / swap32 / bit
//   :26-27, :216-217 0x54 是连接时秤推的旧存档（实测 13.05kg 且时钟不准），必须忽略
//
// 字节序结论（务必理解）：Kotlin parse 用 swap32(be32(b,2))——
//   be32 把 b[2..5] 按大端读成 int，swap32 再翻转字节序，净效果 = 把 b[2..5] 当小端(le32)读。
//   故 kgRaw = (le32(b[2..5]) & 0x3FFFF) / 1000.0，locked = bit(le32(b[2..5]), 31)。
//   time4：swap32 后按大端输出 = sec 的小端 4 字节。
//
// 分层铁律：domain 纯函数，禁止 import package:flutter 与任何 BLE 插件（仅 dart 标准库 + domain 内部）。

import 'js_compat.dart';

/// 定长帧长度（ScaleSync.kt:32 FRAME）
const int kScaleFrameLen = 20;

/// 线型：0x51 = 实时体重流（唯一可信源，ScaleSync.kt:33 W_LIVE）
const int kWireLive = 0x51;

/// 线型：0x54 = 秤在连接时推送的旧存档记录（ScaleSync.kt 注释 :22/:26-27）。
/// 实测 13.05kg 且秤时钟不准，当最终值会记错体重——parse 层直接忽略（返回 null），
/// 此常量仅用于登记语义，不参与过滤。
const int kWireOldStore = 0x54;

/// 握手控制/同步线型（ScaleSync.kt:34-35 W_CONTROL / W_SYNC）
const int _wireControl = 0x5F;
const int _wireSync = 0x62;

/// 握手校时子命令 / 同步子命令（ScaleSync.kt:190-192 buildFrame 第 0 参）
const int _cmdTime = 0x16;
const int _cmdSync = 0x04;

/// 体重克数掩码（ScaleSync.kt:247 WEIGHT_MASK）
const int kWeightMask = 0x3FFFF;

/// 同步请求帧 body 1（ScaleSync.kt:249-252 照抄，15 字节）
const List<int> kSyncBody1 = <int>[
  0, 1, 0xAF, 0xB6, 0x17, 0x1D, 1, //
  0, 2, 0xB4, 0xC6, 0x1B, 0x56, 1, 0, //
];

/// 同步请求帧 body 2（ScaleSync.kt:253-256 照抄，15 字节）
const List<int> kSyncBody2 = <int>[
  1, 3, 0xA5, 0xF8, 0x11, 0x1D, 2, //
  0, 4, 0xB4, 0xC6, 0x1B, 0x1D, 1, 0, //
];

/// CRC：sum(f[2..18]) & 0x1F（ScaleSync.kt:276-280 crc）
int frameCrc(List<int> f) {
  var sum = 0;
  for (var i = 2; i <= 18; i++) {
    sum += f[i] & 0xFF;
  }
  return sum & 0x1F;
}

/// 秒 → 4 字节小端（等价 ScaleSync.kt:268-274 time4：swap32 后按大端输出 = 小端）
List<int> time4LE(int epochSeconds) {
  final v = epochSeconds & 0xFFFFFFFF;
  return <int>[
    v & 0xFF,
    (v >> 8) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 24) & 0xFF,
  ];
}

/// 构造 20 字节定长帧（ScaleSync.kt:258-266 buildFrame）：
/// AF/45 头、f[2]=cmd、body 落 f[3..]、f[18]=wireType、f[19]=crc。
/// body 最长 15（f[3..17]）；短于 15 时剩余位保持 0；不越界。
List<int> buildFrame(int cmd, int wireType, List<int> body) {
  final f = List<int>.filled(kScaleFrameLen, 0);
  f[0] = 0xAF;
  f[1] = 0x45;
  f[2] = cmd & 0xFF;
  for (var i = 0; i < body.length; i++) {
    f[3 + i] = body[i] & 0xFF;
  }
  f[18] = wireType & 0xFF;
  f[19] = frameCrc(f);
  return f;
}

/// 握手三帧（ScaleSync.kt:187-192 handshake）：
/// 0x16/0x5F 校时帧（time4(now)+0x20+10 个 0）+ 两条 0x04/0x62 SYNC 帧。
/// 返回类型用 `List<List<int>>`（3 条 20 字节帧），比简报 Interfaces 写的 `List<int>`
/// 更贴合"3 帧"语义与 T3 逐帧下发（见报告偏离登记）。
List<List<int>> handshakeFrames(int epochSeconds) {
  final timeBody = <int>[
    ...time4LE(epochSeconds),
    0x20,
    ...List<int>.filled(10, 0),
  ];
  return <List<int>>[
    buildFrame(_cmdTime, _wireControl, timeBody),
    buildFrame(_cmdSync, _wireSync, kSyncBody1),
    buildFrame(_cmdSync, _wireSync, kSyncBody2),
  ];
}

/// 解析后的实时帧载荷（ScaleSync.kt:218-220 emit 入参）
class ScaleFrame {
  const ScaleFrame({required this.kgRaw, required this.locked});

  /// 原始体重（千克，未经 round）
  final double kgRaw;

  /// 秤判定"最终值"位（bit31）
  final bool locked;
}

/// 读 b[off..off+3] 为小端 32 位无符号整数（净效果对齐 swap32(be32)，见文件头）
int _le32(List<int> b, int off) =>
    (b[off] & 0xFF) | ((b[off + 1] & 0xFF) << 8) | ((b[off + 2] & 0xFF) << 16) | ((b[off + 3] & 0xFF) << 24);

/// 解析一条实时体重帧（ScaleSync.kt:212-222 parse）。
/// 返回 null 表示非法/忽略：长度≠20、帧头非 AF/45、crc 不匹配、线型非 0x51（含 0x54 旧存档）。
ScaleFrame? parseScaleFrame(List<int> b) {
  if (b.length != kScaleFrameLen) return null;
  if ((b[0] & 0xFF) != 0xAF || (b[1] & 0xFF) != 0x45) return null;
  if (frameCrc(b) != (b[19] & 0x1F)) return null;
  // 只信 0x51 实时流；0x54 是秤在连接时推送的旧存档（实测 13.05kg 且时钟不准），
  // 当最终值会记错体重，必须忽略（ScaleSync.kt:216-218）
  if ((b[18] & 0xFF) != kWireLive) return null;
  final flags = _le32(b, 2);
  return ScaleFrame(
    kgRaw: (flags & kWeightMask) / 1000.0,
    locked: ((flags >> 31) & 1) == 1,
  );
}

/// 过滤后可上报的体重（ScaleSync.kt:224-237 emit）
class ScaleEmit {
  const ScaleEmit({required this.kg, required this.locked, required this.changed});

  /// round 两位小数后的体重
  final double kg;

  /// 是否为秤判定的最终值
  final bool locked;

  /// 是否需要上报：locked 恒 true（走 commit 一次）；非 locked 时 = kg != lastKg
  final bool changed;
}

/// 对解析出的帧做 emit 端过滤（ScaleSync.kt:224-237）：
/// - kg = round(rawKg*100)/100（用 jsRound 保真，本域 kg*100 恒非负，与 Kotlin Math.round 一致）
/// - kg 不在 2.0..300.0 → 丢弃（返回 null）
/// - locked → 直通，changed=true（Kotlin 用 lockedSent 去重一次，交由上层编排 T3 处理）
/// - 非 locked → changed = (kg != lastKg)
ScaleEmit? filterReading(ScaleFrame f, {double? lastKg}) {
  final kg = jsRound(f.kgRaw * 100.0) / 100.0;
  if (kg < 2.0 || kg > 300.0) return null;
  if (f.locked) {
    return ScaleEmit(kg: kg, locked: true, changed: true);
  }
  final changed = kg != lastKg;
  return ScaleEmit(kg: kg, locked: false, changed: changed);
}
