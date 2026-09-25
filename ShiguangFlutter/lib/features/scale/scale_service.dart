// ShiguangFlutter/lib/features/scale/scale_service.dart
// M4-T3 体脂秤编排层：ScaleTransport 抽象 + ScaleService 状态机 + Provider。
//
// 编排规则逐字移植 HealthyDiet/.../ScaleSync.kt：
//   :87-97  扫描过滤 name.startsWith('AFU-')（在 transport 实现内）
//   :136-148 订阅全部 NOTIFY/INDICATE 特征（transport 实现内）
//   :150-157 写特征 af000002 前缀否则退化任一可写（transport 实现内）
//   :187-193 握手三帧逐帧下发（本文件，调 domain handshakeFrames）
//   :37-38  扫描 30s / 读数 90s 超时（本文件，构造参数可注入）
//   :57/:81/:106/:228-231 lockedSent 会话状态由本文件持有（T2 账本点名）：
//            locked 读数只发一次并立即 finish('ok')，漏了会重复 commit。
//   :233-235 非 locked 同值去重（lastKg，经 filterReading）
//   :63-75  无蓝牙/未开 → no-bluetooth（transport 抛 TransportException）
//
// 分层：本文件禁止 import flutter_blue_plus/permission_handler——插件只出现在
// blue_plus_transport.dart（唯一 import 插件的文件）。测试用 FakeTransport 注入。

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/scale_protocol.dart';
import 'blue_plus_transport.dart';

/// transport 层错误：kind ∈ 'no-bluetooth' | 'connect-fail'（对应 Kotlin
/// ScaleSync.kt:67-71 蓝牙不可用 与 :130 连接断开/失败 两类终态）。
class TransportException implements Exception {
  const TransportException(this.kind, [this.message = '']);

  final String kind;
  final String message;

  @override
  String toString() => 'TransportException($kind: $message)';
}

/// 一条已连接会话（扫描+连接+订阅完成后交给编排层的句柄）。
abstract class TransportSession {
  /// 逐帧下发（握手帧等）；失败抛异常 → 编排层映射 connect-fail
  Future<void> writeFrame(List<int> frame);

  /// 断开连接并释放订阅；幂等
  Future<void> close();
}

/// BLE 传输抽象。真机实现 = BluePlusTransport；单测实现 = FakeTransport。
abstract class ScaleTransport {
  /// 通知字节流。**transport 级广播流**：scanAndConnect 成功后，实现把所选
  /// NOTIFY/INDICATE 特征的 onValueReceived 汇入此流；会话结束后流保持可用
  /// （支持 cancel→再 start 复用同一 transport），跨会话不投递旧帧（订阅后
  /// 才收）。生命周期选型说明见 task-3 报告。
  Stream<List<int>> notifications();

  /// 按名称前缀扫描并连接、发现服务、订阅通知。
  /// 返回 null = 超时没扫到（scan-timeout）；抛 [TransportException] = 蓝牙
  /// 不可用/连接失败；返回会话 = 成功。
  Future<TransportSession?> scanAndConnect({
    required String namePrefix,
    required Duration timeout,
  });

  /// 运行时权限（Android 12+ 蓝牙扫描/连接；≤30 定位）。true = 已齐。
  Future<bool> ensurePermissions();
}

/// 一条体重读数（对应 Kotlin OnWeight 回调 :40）
class ScaleReading {
  const ScaleReading({required this.kg, required this.stable});

  final double kg;

  /// true = 秤判定的最终值（locked 帧）
  final bool stable;
}

/// 一次同步的终态。status ∈
/// ok | scan-timeout | connect-fail | read-timeout | no-bluetooth |
/// permission-denied | cancelled
/// （cancelled 为第 7 个程序化终态：仅 cancel() 产生，UI 侧静默即可，
/// 登记偏离——简报枚举未列，但 cancel 必须让进行中的 start() 有确定归宿。）
class ScaleOutcome {
  const ScaleOutcome(this.status, {this.kg});

  final String status;

  /// status == 'ok' 时为 locked 体重；其余为 null
  final double? kg;

  @override
  String toString() => 'ScaleOutcome($status, kg: $kg)';
}

/// 秤同步编排状态机：idle→scanning→handshake→streaming→done。
class ScaleService {
  ScaleService(
    this._transport, {
    this.scanTimeout = const Duration(seconds: 30), // ScaleSync.kt:37
    this.readTimeout = const Duration(seconds: 90), // ScaleSync.kt:38
    int Function()? nowSeconds,
  }) : _nowSeconds = nowSeconds ?? _defaultNowSeconds;

  static int _defaultNowSeconds() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final ScaleTransport _transport;
  final Duration scanTimeout;
  final Duration readTimeout;
  final int Function() _nowSeconds;

  /// 读数出口（broadcast：UI listen，测试先 listen 再 start）
  final StreamController<ScaleReading> _readings =
      StreamController<ScaleReading>.broadcast();

  Future<ScaleOutcome>? _inflight;
  Completer<ScaleOutcome>? _pending;
  StreamSubscription<List<int>>? _notifySub;
  TransportSession? _session;
  Timer? _readTimer;

  // ===== 会话状态（ScaleSync.kt:56-57 lastKg / lockedSent）=====
  double? _lastKg;
  bool _lockedSent = false;

  Stream<ScaleReading> get readings => _readings.stream;

  /// 发起一次同步。会话进行中再调 → 直接返回进行中的同一个 Future
  /// （不并发两条会话；Kotlin 是 start 前置 stop，这里用重入等价锁定）。
  /// 注意（I1(a)）：cancel() 返回后旧 _run 的迟到 await（scanAndConnect 等）
  /// 可能仍在收尾，该窗口内 start() 返回的仍是本次 cancelled 的同一个
  /// Future——重入保护延迟到 _run 真正落地才解除，杜绝双会话交叉。
  Future<ScaleOutcome> start() {
    final inflight = _inflight;
    if (inflight != null) return inflight;
    final future = _run();
    _inflight = future;
    return future;
  }

  /// 取消进行中的会话；无会话时为空操作（幂等）。
  Future<void> cancel() async {
    final pending = _pending;
    if (pending == null) return;
    _finish(const ScaleOutcome('cancelled'));
    await pending.future;
  }

  Future<ScaleOutcome> _run() {
    final pending = Completer<ScaleOutcome>();
    _pending = pending;
    _lastKg = null; // :81 lastKg = -1.0
    _lockedSent = false; // :82 lockedSent = false

    // 读数超时从发起即计时（Kotlin :83-84 readDeadline 在 start 里 postDelayed）
    _readTimer = Timer(readTimeout, () {
      _finish(const ScaleOutcome('read-timeout')); // :83 "读取超时"
    });

    // I1(a)：_inflight 必须等 _runSession 的全部 await 真正落地后才解除。
    // 若在 _finish 里提前清，旧 _run 仍可能卡在 scanAndConnect（真机秒级），
    // cancel→立即重来会放行第二条会话，与旧会话迟到的 close 在 transport
    // 层交叉断连（评审 I1，test 有复现用例钉死）。
    return _runSession(pending).whenComplete(() {
      _inflight = null;
      if (identical(_pending, pending)) _pending = null; // 双保险，防迟到路径漏清
    });
  }

  Future<ScaleOutcome> _runSession(Completer<ScaleOutcome> pending) async {
    try {
      if (!await _transport.ensurePermissions()) {
        return await _terminate(pending, const ScaleOutcome('permission-denied'));
      }
      if (pending.isCompleted) return await pending.future; // 等待期间已被 cancel/超时终止

      TransportSession? session;
      try {
        session = await _transport.scanAndConnect(
            namePrefix: 'AFU-', timeout: scanTimeout);
      } on TransportException catch (e) {
        // :67-71 蓝牙不可用；:130 连接断开/失败
        return await _terminate(
            pending,
            ScaleOutcome(
                e.kind == 'no-bluetooth' ? 'no-bluetooth' : 'connect-fail'));
      } catch (_) {
        return await _terminate(pending, const ScaleOutcome('connect-fail'));
      }
      if (session == null) {
        return await _terminate(pending, const ScaleOutcome('scan-timeout')); // :85 "30 秒没找到秤"
      }
      if (pending.isCompleted) {
        // 等待期间会话已被终止：立刻归还刚拿到的连接，不留悬空 GATT
        unawaited(session.close());
        return await pending.future;
      }
      _session = session;

      // 先订阅通知流，再握手（Kotlin :147-159 订阅成功后延迟发握手）
      _notifySub = _transport.notifications().listen(_onBytes);

      try {
        for (final frame in handshakeFrames(_nowSeconds())) {
          await session.writeFrame(frame); // ScaleSync.kt:187-193
        }
      } catch (_) {
        return await _terminate(pending, const ScaleOutcome('connect-fail'));
      }
      return await pending.future;
    } catch (_) {
      // 编排层自身的意外错误：不静默挂死，归入 connect-fail
      return await _terminate(pending, const ScaleOutcome('connect-fail'));
    }
  }

  /// 通知字节 → 协议解析 → emit 过滤 → readings（编排规则核心，对齐 :212-237）
  void _onBytes(List<int> bytes) {
    if (_pending == null || _pending!.isCompleted) return;
    final frame = parseScaleFrame(bytes); // 非 0x51/坏 crc/坏头/坏长度 → null（含 0x54 忽略）
    if (frame == null) return;
    final emit = filterReading(frame, lastKg: _lastKg);
    if (emit == null || !emit.changed) return;
    if (emit.locked) {
      if (_lockedSent) return; // ScaleSync.kt:229：locked 只发一次
      _lockedSent = true;
      _readings.add(ScaleReading(kg: emit.kg, stable: true));
      _finish(ScaleOutcome('ok', kg: emit.kg)); // :232 finish("ok")
    } else {
      _lastKg = emit.kg;
      _readings.add(ScaleReading(kg: emit.kg, stable: false));
    }
  }

  /// M2：单一终态守卫——pending 若已被 cancel()/超时抢先完成，本会话一切
  /// 等待方以已完成的终态为准，禁止再产出第二终态（否则 start 与 cancel 两
  /// waiter 拿到不同结果）。pending 未完成时才走 _finish 落定新终态。
  Future<ScaleOutcome> _terminate(
      Completer<ScaleOutcome> pending, ScaleOutcome outcome) {
    if (pending.isCompleted) return pending.future;
    return Future.value(_finish(outcome));
  }

  /// 终止会话：清 timer/订阅/连接，完成 outcome。幂等。
  /// 注意（I1(a)）：这里**不**清 _inflight——重入保护的解除延迟到 _run 的
  /// 全部 await（含此处之后 _runSession 里的迟到 scanAndConnect）真正落地，
  /// 见 _run 注释与 test/scale_service_test.dart 的 I1 复现用例。
  ScaleOutcome _finish(ScaleOutcome outcome) {
    _readTimer?.cancel();
    _readTimer = null;
    final sub = _notifySub;
    _notifySub = null;
    sub?.cancel();
    final session = _session;
    _session = null;
    session?.close(); // fire-and-forget：transport close 幂等且不抛
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(outcome);
    }
    return outcome;
  }
}

// ===== Provider（组合根不接线，T4 测试自行 override）=====

/// 默认真机传输：BluePlusTransport
final scaleServiceProvider = Provider<ScaleService>(
    (ref) => ScaleService(BluePlusTransport()));

/// live 体重读数预览流（Task 4 体重卡 listen 这个）
final scaleReadingsProvider = StreamProvider<ScaleReading>(
    (ref) => ref.watch(scaleServiceProvider).readings);
