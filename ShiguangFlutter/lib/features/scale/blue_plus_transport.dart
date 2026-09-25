// ShiguangFlutter/lib/features/scale/blue_plus_transport.dart
// M4-T3：ScaleTransport 的 flutter_blue_plus 薄实现。**全工程唯一 import
// BLE/权限插件的文件**（编排层 scale_service.dart 只依赖抽象，用 FakeTransport 测）。
// 无单测（插件走平台通道，VM 测试环境无真实蓝牙），真机验收；analyze 必须过。
//
// 插件 API 逐一对照安装源核实（禁止照记忆写）：
//   flutter_blue_plus 2.3.13
//     lib/src/flutter_blue_plus.dart :269 startScan({withServices, withNames,
//       withKeywords, Duration? timeout, ...})（timeout 由插件内部到点停扫）、
//       :83 scanResults → Stream<List<ScanResult>>、:412 stopScan()、
//       :195 adapterState → Stream<BluetoothAdapterState>（首事件即当前态）
//     lib/src/bluetooth_device.dart :106 connect({required License license,
//       Duration timeout = 35s, int? mtu = 512, bool autoConnect})——2.x 起
//       license 为必填枚举；:207 disconnect({timeout, queue, androidDelay})；
//       :262 discoverServices({timeout = 15}) → List<BluetoothService>；
//       :34 platformName / :41 advName
//     lib/src/bluetooth_characteristic.dart :256 setNotifyValue(bool, {timeout})、
//       :99 onValueReceived → Stream<List<int>>（仅通知到达）、
//       :189 write(List<int>, {withoutResponse, allowLongWrite, timeout})、
//       :28 properties → CharacteristicProperties{notify,indicate,write,
//       writeWithoutResponse}
//     platform_interface 9.0.3 guid.dart :68 Guid.str → 128-bit 厂商 UUID 返回
//       小写全串 → startsWith('af000002') 与 Kotlin uuid.toString() 语义一致
//   permission_handler 12.0.1（pubspec.yaml:23 精确钉，非 caret）extension
//     PermissionActions.request() → PermissionStatus（isGranted）；
//     permission_handler_android 13.0.1（随 12.0.1 解析，见 pubspec.lock）
//     PermissionUtils.java:283-295：API<31 时 BLUETOOTH_SCAN/CONNECT 不进
//     请求名单（返回 granted）→ 与 H5 壳 MainActivity.kt:57-60 的
//     「≥31 要蓝牙双权限，≤30 要精确定位」分流一致。
//
// 编排语义对应 ScaleSync.kt：:87-97 名称前缀过滤（advName 优先，回退
// platformName）；:136-148 订阅全部 NOTIFY/INDICATE；:150-157 写特征
// af000002 前缀否则退化任一可写。

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'scale_service.dart';

/// flutter_blue_plus 实现。个人/非商业项目按插件许可枚举选
/// [License.nonprofit]（2.3.13 connect 必填参数，见 LICENSE 条款）。
class BluePlusTransport implements ScaleTransport {
  // I1(b)：device / 写特征 / 通知订阅**全部收进 _BluePlusSession 各持各的**，
  // transport 实例不再存会话状态。此前它们挂在字段上，cancel→立即重来时旧
  // 会话迟到的 close() 会从字段读到新会话的 device/subs → 断掉新会话 GATT、
  // 取消新会话订阅（评审 I1 交叉断连根因）。transport 级只保留通知广播流
  // （跨会话复用，属流管道而非会话资源）。
  /// transport 级广播通知流：跨会话复用，close 会话只退订不关流
  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> notifications() => _notifications.stream;

  // ============================ 权限 ============================

  @override
  Future<bool> ensurePermissions() async {
    // 对齐 MainActivity.kt:57-60 分流：API≥31 → 蓝牙扫描+连接；≤30 → 精确定位。
    final bt = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    if (!bt.values.every((s) => s.isGranted || s.isLimited)) return false;
    // API<31 时上面两项恒 granted（插件源码行为），真机扫描靠定位权限
    final sdk = _androidSdkInt();
    if (sdk != null && sdk <= 30) {
      final loc = await Permission.location.request();
      return loc.isGranted;
    }
    return true;
  }

  /// 从 Platform.operatingSystemVersion（Android 形如 "Android 12 (API 31)"）
  /// 解析 SDK 整型；解析失败返回 null → 按 ≥31 处理（只走蓝牙权限分支）。
  int? _androidSdkInt() {
    if (!Platform.isAndroid) return null;
    final m = RegExp(r'API\s+(\d+)').firstMatch(Platform.operatingSystemVersion);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  // ============================ 扫描+连接 ============================

  /// 扫描代际（M4-T4 死区修复配套）：每次 scanAndConnect 进入即取新号。
  /// flutter_blue_plus 的扫描是**全局单例**（scanResults 广播给所有在听者，
  /// stopScan 影响所有扫描），编排层 cancel 后允许立即重来，于是会出现
  /// "旧 scanAndConnect 的迟到清理撞上新扫描在跑"。代际守卫保证迟到清理
  /// 不 stopScan 掐断新一代——这是两条并发扫描唯一能互相伤害的通道。
  int _scanOp = 0;

  @override
  Future<TransportSession?> scanAndConnect({
    required String namePrefix,
    required Duration timeout,
    Future<void>? cancelSignal,
  }) async {
    final myOp = ++_scanOp;
    // 蓝牙开关检查（ScaleSync.kt:67-75 的三段判断归并为 no-bluetooth）
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      throw const TransportException('no-bluetooth', '蓝牙未开或不支持');
    }

    // 防「startScan already called」：上一轮异常退出可能残留扫描（isScanningNow 有守卫）
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }

    final found = Completer<BluetoothDevice>();
    final scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        // ScaleSync.kt:89-91：广播名优先，回退设备名；startsWith('AFU-')
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        if (name.startsWith(namePrefix) && !found.isCompleted) {
          found.complete(r.device);
        }
      }
    });

    BluetoothDevice device;
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      // 等扫描结果。超时/协作取消都**包成值**再进 Future.any：若让错误直接
      // 进竞速，取消先行落地后迟到的 TimeoutException 会变成无人处理的
      // unhandled error（Future.any 分出胜负后就不再消费其余 future）。
      final scanWait = found.future //
          .timeout(timeout + const Duration(seconds: 1),
              onTimeout: () => throw TimeoutException('scan'))
          .then<Object?>((d) => _ScanFound(d))
          .catchError((Object e) => _ScanFailed(e));
      final raced = await Future.any(<Future<Object?>>[
        scanWait,
        if (cancelSignal != null) cancelSignal.then<Object?>((_) => _kAborted),
      ]);
      if (identical(raced, _kAborted)) {
        // 协作收尾（scale_service 契约）：不再连接任何设备；迟到清理
        // 经代际守卫，若新扫描已开则不碰全局 stopScan。返回 null 不抛。
        await _endScan(myOp, scanSub);
        return null;
      }
      if (raced is _ScanFailed) {
        // 原超时 → scan-timeout（null）；其余 → connect-fail
        await _endScan(myOp, scanSub);
        final e = raced.error;
        if (e is TimeoutException) return null; // 编排层 → scan-timeout
        if (e is TransportException) throw e;
        throw TransportException('connect-fail', '$e');
      }
      device = (raced as _ScanFound).device;
      await _endScan(myOp, scanSub); // ScaleSync.kt:122 扫到即停扫
    } on TransportException {
      await _endScan(myOp, scanSub);
      rethrow;
    } catch (e) {
      await _endScan(myOp, scanSub);
      throw TransportException('connect-fail', '$e');
    }

    // I1(b)：本会话独占的资源全部局持有，成功后打包进 _BluePlusSession
    final charSubs = <StreamSubscription<List<int>>>[];
    try {
      await device.connect(license: License.nonprofit);
      final services = await device.discoverServices();

      // :136-148 订阅全部 NOTIFY/INDICATE 特征
      final notifies = <BluetoothCharacteristic>[
        for (final s in services)
          for (final c in s.characteristics)
            if (c.properties.notify || c.properties.indicate) c,
      ];
      if (notifies.isEmpty) {
        // ScaleSync.kt:143-145 "秤没有通知特征，无法读数"
        throw const TransportException('connect-fail', '无通知特征');
      }

      // :150-157 写特征：af000002 前缀优先，否则退化任一可写
      final all = <BluetoothCharacteristic>[
        for (final s in services) ...s.characteristics,
      ];
      final writeChr = all.where((c) => c.uuid.str.startsWith('af000002')).firstOrNull ??
          all.where((c) => c.properties.write || c.properties.writeWithoutResponse)
              .firstOrNull;
      if (writeChr == null) {
        // Kotlin 无写特征时静默跳过握手（最终吃读超时）；这里显式快速失败
        throw const TransportException('connect-fail', '无可写特征');
      }

      // 先建立订阅再交给编排层握手（Kotlin :147-159 时序）
      for (final c in notifies) {
        await c.setNotifyValue(true);
        charSubs.add(c.onValueReceived.listen(_notifications.add));
      }
      return _BluePlusSession(device, writeChr, charSubs);
    } on TransportException {
      await _teardown(device, charSubs);
      rethrow;
    } catch (e) {
      // :130 连接失败/断开
      await _teardown(device, charSubs);
      throw TransportException('connect-fail', '$e');
    }
  }

  /// 扫描迟到清理：退订恒做；全局 stopScan 只在**仍是自己这一代**时做
  /// （已有更新代 scanAndConnect 在跑时，扫描归新调用方管辖，stopScan
  /// 会掐断新扫描——这正是编排层兜底注释里"真机实现必须协作"的部分）。
  /// 参数取 covariant 超类型：scanResults 订阅是 `List<ScanResult>` 流，
  /// 与通知流的 `List<int>` 流元素类型不同，此处只用 cancel()。
  Future<void> _endScan(int myOp, StreamSubscription<Object?> sub) async {
    await sub.cancel();
    if (myOp != _scanOp) return;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // 插件内部 timeout 到点已自停时 stopScan 可能抛：不影响结果
    }
  }

  Future<void> _teardown(
      BluetoothDevice? device, List<StreamSubscription<List<int>>> subs) async {
    for (final s in subs) {
      await s.cancel();
    }
    subs.clear();
    try {
      if (device != null && device.isConnected) {
        await device.disconnect();
      }
    } catch (_) {
      // 断开失败不再抛：会话已作废
    }
  }
}

/// 协作取消竞速哨兵（scanAndConnect 内部）。
const Object _kAborted = _AbortToken();

class _AbortToken {
  const _AbortToken();
}

/// 扫描等待结果包装：把"成功/超时/异常"全部包成**值**参与 Future.any，
/// 取消胜出后迟到完成只是无人消费的值，不会炸 unhandled error。
class _ScanFound {
  const _ScanFound(this.device);
  final BluetoothDevice device;
}

class _ScanFailed {
  const _ScanFailed(this.error);
  final Object error;
}

/// 一条已连接会话。**自带** device/写特征/订阅三份资源（I1(b)），close 只
/// 可能影响自己，不再经由任何 transport 共享字段——旧会话迟到的 close 与
/// 新会话建立并发时不会交叉断连。
class _BluePlusSession implements TransportSession {
  _BluePlusSession(this._device, this._writeChr, this._charSubs);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChr;
  final List<StreamSubscription<List<int>>> _charSubs;
  bool _closed = false;

  @override
  Future<void> writeFrame(List<int> frame) async {
    final c = _writeChr;
    if (c == null) throw const TransportException('connect-fail', '已断开');
    // ScaleSync.kt:197-199：有 write 属性走有响应写，否则 writeWithoutResponse
    await c.write(frame, withoutResponse: !c.properties.write);
  }

  @override
  Future<void> close() async {
    if (_closed) return; // 幂等
    _closed = true;
    final device = _device;
    _device = null;
    _writeChr = null;
    for (final s in _charSubs) {
      await s.cancel();
    }
    _charSubs.clear();
    try {
      if (device != null && device.isConnected) {
        await device.disconnect();
      }
    } catch (_) {
      // 幂等 close：断开异常吞掉
    }
  }
}
