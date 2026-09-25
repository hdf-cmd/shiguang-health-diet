// ShiguangFlutter/test/scale_service_test.dart
// M4-T3 体脂秤编排层单测：FakeTransport 注入，锁死 ScaleSync.kt 移植语义。
// 权威源：HealthyDiet/.../ScaleSync.kt :57/:81/:106 lockedSent、:83-85 读超时、
// :85 扫描超时、:91 AFU- 前缀、:129-131 断连、:187-193 握手三帧、:224-237 emit 去重。
// FakeTransport/liveFrame/settle 已抽到 test/scale_fakes.dart（M4-T4 起
// profile_screen_test 同用，两处共享）。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/scale_protocol.dart';
import 'package:shiguang_flutter/features/scale/scale_service.dart';

import 'scale_fakes.dart';

void main() {
  // 测试用毫秒级超时（构造参数可注入是硬要求）
  ScaleService build(FakeTransport t) => ScaleService(
        t,
        scanTimeout: const Duration(milliseconds: 300),
        readTimeout: const Duration(milliseconds: 1500),
      );

  group('ScaleService 正常序列', () {
    test('3×非锁定渐进值→locked：readings 三条 + outcome ok/66.66', () async {
      final t = FakeTransport();
      final svc = build(t);
      final readings = <ScaleReading>[];
      svc.readings.listen(readings.add);

      final future = svc.start();
      await settle();
      expect(t.notificationsSubscribed, isTrue); // 连接后必须已订阅通知流
      expect(t.lastScanPrefix, 'AFU-'); // ScaleSync.kt:31 前缀过滤
      // M4：编排层 scanTimeout 必须原样注入 transport（钉死注入链）
      expect(t.lastScanTimeout, svc.scanTimeout);

      t.emit(liveFrame(60.1));
      t.emit(liveFrame(60.5));
      t.emit(liveFrame(66.66, locked: true));
      final outcome = await future;

      expect(outcome.status, 'ok');
      expect(outcome.kg, 66.66);
      expect(readings.map((r) => r.kg).toList(), [60.1, 60.5, 66.66]);
      expect(readings.map((r) => r.stable).toList(), [false, false, true]);
      expect(t.sessions.single.closed, isTrue); // finish → close
    });

    test('握手三帧逐帧写出，等于 handshakeFrames(now)，时间窗 ±2s', () async {
      final t = FakeTransport();
      final svc = build(t);
      final future = svc.start();
      final t0 = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await future;
      final t1 = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      expect(t.writes.length, 3);
      for (final w in t.writes) {
        expect(w.length, kScaleFrameLen);
        expect(frameCrc(w), w[19]); // 写出的帧自身 crc 必须合法
      }
      // 帧2/帧3 与 SYNC 帧逐字节一致
      final expected = handshakeFrames(t0);
      expect(t.writes[1], expected[1]);
      expect(t.writes[2], expected[2]);
      // 帧1 校时帧：从 writes[0][3..6] 反解秒数，须在 [t0-2, t1+2] 窗内，
      // 且除 time4 外其余字节与 handshakeFrames(该秒) 帧1 全等
      final sec = t.writes[0][3] |
          (t.writes[0][4] << 8) |
          (t.writes[0][5] << 16) |
          (t.writes[0][6] << 24);
      expect(sec, inInclusiveRange(t0 - 2, t1 + 2));
      expect(t.writes[0], handshakeFrames(sec)[0]);
    });
  });

  group('ScaleService 去重/忽略', () {
    test('重复 locked 只发一次（lockedSent，ScaleSync.kt:57/:229）', () async {
      final t = FakeTransport();
      final svc = build(t);
      final readings = <ScaleReading>[];
      svc.readings.listen(readings.add);

      final future = svc.start();
      await settle();
      t.emit(liveFrame(66.66, locked: true));
      final outcome = await future;
      // 会话已结束；再推第二帧 locked 不得再发读数/再改 outcome
      t.emit(liveFrame(66.66, locked: true));
      await settle();

      expect(outcome.status, 'ok');
      expect(readings.length, 1);
      expect(readings.single.stable, isTrue);
    });

    test('同值非锁定只发一次（lastKg 去重，ScaleSync.kt:233）', () async {
      final t = FakeTransport();
      final svc = build(t);
      final readings = <ScaleReading>[];
      svc.readings.listen(readings.add);

      final future = svc.start();
      await settle();
      t.emit(liveFrame(60.1));
      t.emit(liveFrame(60.1));
      t.emit(liveFrame(60.5));
      t.emit(liveFrame(66.66, locked: true));
      await future;

      expect(readings.map((r) => r.kg).toList(), [60.1, 60.5, 66.66]);
    });

    test('0x54 旧存档 / 坏 crc / 坏头 / 坏长度帧全部被忽略', () async {
      final t = FakeTransport();
      final svc = build(t);
      final readings = <ScaleReading>[];
      svc.readings.listen(readings.add);

      final future = svc.start();
      await settle();
      t.emit(liveFrame(13.05, locked: true, wireType: 0x54)); // 旧存档
      final badCrc = liveFrame(70.0);
      badCrc[19] = (badCrc[19] + 7) & 0x1F;
      t.emit(badCrc);
      final badHeader = liveFrame(71.0)..[0] = 0x00;
      t.emit(badHeader);
      t.emit(liveFrame(72.0).sublist(0, 19)); // 长度≠20
      t.emit(liveFrame(60.1));
      t.emit(liveFrame(66.66, locked: true));
      final outcome = await future;

      expect(readings.map((r) => r.kg).toList(), [60.1, 66.66]);
      expect(outcome.kg, 66.66);
    });
  });

  group('ScaleService 错误路径', () {
    test('scanAndConnect 返回 null → scan-timeout', () async {
      final t = FakeTransport(scanReturnsSession: false);
      final svc = build(t);
      final outcome = await svc.start();
      expect(outcome.status, 'scan-timeout');
      expect(outcome.kg, isNull);
    });

    test('scanAndConnect 抛 TransportException(no-bluetooth) → no-bluetooth',
        () async {
      final t = FakeTransport(
          scanError: const TransportException('no-bluetooth', '蓝牙未开'));
      final svc = build(t);
      final outcome = await svc.start();
      expect(outcome.status, 'no-bluetooth');
    });

    test('scanAndConnect 抛其它异常 → connect-fail', () async {
      final t = FakeTransport(scanError: Exception('gatt 133'));
      final svc = build(t);
      final outcome = await svc.start();
      expect(outcome.status, 'connect-fail');
    });

    test('ensurePermissions 拒绝 → permission-denied 且不再扫描', () async {
      final t = FakeTransport(permissionsGranted: false);
      final svc = build(t);
      final outcome = await svc.start();
      expect(outcome.status, 'permission-denied');
      expect(t.scanAndConnectCalls, 0);
    });

    test('读数超时 → read-timeout 且关闭会话', () async {
      final t = FakeTransport();
      final svc = ScaleService(
        t,
        scanTimeout: const Duration(milliseconds: 300),
        readTimeout: const Duration(milliseconds: 60),
      );
      final outcome = await svc.start();
      expect(outcome.status, 'read-timeout');
      expect(t.sessions.single.closed, isTrue);
    });
  });

  group('ScaleService cancel/重入', () {
    test('cancel 幂等：进行中取消→cancelled，重复 cancel 不炸，可再 start',
        () async {
      final t = FakeTransport();
      final svc = build(t);
      final future = svc.start();
      await settle();
      await svc.cancel();
      final outcome = await future;
      expect(outcome.status, 'cancelled');

      await svc.cancel(); // 二次 cancel 幂等
      expect(t.sessions.single.closed, isTrue);

      // 取消后可重新发起（Kotlin start 前置 stop 语义）
      final next = svc.start();
      await settle();
      t.emit(liveFrame(66.66, locked: true));
      final outcome2 = await next;
      expect(outcome2.status, 'ok');
      expect(t.scanAndConnectCalls, 2);
    });

    test('重入 start 返回同一进行中 outcome（不并发两条会话）', () async {
      final t = FakeTransport();
      final svc = build(t);
      final a = svc.start();
      final b = svc.start();
      await settle();
      t.emit(liveFrame(66.66, locked: true));
      final oa = await a;
      final ob = await b;
      expect(identical(a, b), isTrue);
      expect(oa.status, 'ok');
      expect(ob.status, 'ok');
      expect(t.scanAndConnectCalls, 1);
    });

    test('I1+T4：cancel 时旧扫描协作终结（不建会话/不掐新扫描），'
        '重试立刻发起第二条扫描；迟到 close 异步尾巴不串台', () async {
      final t = FakeTransport(gateScans: true);
      final svc = build(t);
      final readings = <ScaleReading>[];
      svc.readings.listen(readings.add);

      final f1 = svc.start();
      await settle();
      expect(t.scanGates.length, 1);
      expect(t.lastCancelSignal, isNotNull); // 编排层必须把取消信号注入扫描

      await svc.cancel();
      expect((await f1).status, 'cancelled'); // 修复后无需等扫描自超时立即落地
      await settle();
      expect(t.scanAborts, 1); // 旧扫描协作终结：不产生会话、不 close
      expect(t.sessions, isEmpty); // 无 GATT 可断 → 无从交叉断连

      final f2 = svc.start(); // 死区已除：不等第一条扫描 ~31s 自超时
      await settle();
      expect(t.scanAndConnectCalls, 2);
      final s2 = t.completeScanGate(1); // gate[0] 已作废永不消费
      await settle();
      expect(s2.transportDisconnected, isFalse); // 旧扫描归还没碰新会话
      expect(t.writes.length, 3); // 新会话握手三帧正常写出

      // 新会话收尾：close 挂异步尾巴（真机 disconnect 未完成）期间再开一条
      t.closeBlocker = Completer<void>();
      t.emit(liveFrame(66.66, locked: true));
      final o2 = await f2;
      expect(o2.status, 'ok');
      expect(o2.kg, 66.66);
      expect(readings.map((r) => r.kg).toList(), [66.66]);

      final f3 = svc.start();
      await settle();
      expect(t.scanAndConnectCalls, 3);
      final s3 = t.completeScanGate(2);
      await settle();
      expect(s3.transportDisconnected, isFalse); // s2 的 close 未串台到 s3
      t.closeBlocker!.complete(); // s2 的"断开落地"发生在 s3 已建立之后
      await settle();
      expect(s2.transportDisconnected, isTrue);
      t.emit(liveFrame(70.0, locked: true));
      final o3 = await f3;
      expect(o3.status, 'ok');
      expect(o3.kg, 70.0);
      expect(readings.map((r) => r.kg).toList(), [66.66, 70.0]);
    });

    test('T4 遗留死区：扫描期 cancel 应立即落地，重试立刻发起第二次扫描',
        () async {
      // 现状（修复前）：cancel() 只落 pending，_run 仍卡在 scanAndConnect，
      // _inflight 不解约 ~31s；期间 start() 返回同一个已 cancelled 的
      // Future——"重试"按钮没反应。本用例钉死修法：cancel 后 f1 立即落地，
      // 再 start 立刻走到第二次 scanAndConnect。
      final t = FakeTransport(gateScans: true);
      final svc = build(t);

      final f1 = svc.start();
      await settle();
      expect(t.scanGates.length, 1);

      await svc.cancel();
      // 修复前 f1 不会在 300ms 内落地（gate 永不完成）→ onTimeout 给出
      // 可断言的哨兵状态，让 RED 是"断言失败"而不是 30s 用例超时。
      final o1 = await f1.timeout(
        const Duration(milliseconds: 300),
        onTimeout: () => const ScaleOutcome('__HUNG__'),
      );
      expect(o1.status, 'cancelled');

      final f2 = svc.start();
      await settle();
      expect(t.scanAndConnectCalls, 2); // 修复前恒 1（重入返回同一 _inflight）
      expect(identical(f1, f2), isFalse); // 修复前恒 true
    });

    test('M2：cancel 与在途握手写异常竞态 → start 与 cancel 两 waiter 同终态',
        () async {
      final t = FakeTransport();
      final svc = build(t);
      t.writeBlocker = Completer<void>(); // 握手第一帧卡在写上（真机秒级）
      final f = svc.start();
      await settle();
      await svc.cancel(); // _finish 关闭会话 → 写通道置空
      t.writeBlocker!.complete(); // 在途写恢复后抛（blue_plus :206-208 形状）
      final o = await f;
      // 修复前：_run 返回 connect-fail，而 cancel() 已拿到 cancelled——双终态
      expect(o.status, 'cancelled');
      expect(t.writes, isEmpty);
    });
  });
}
