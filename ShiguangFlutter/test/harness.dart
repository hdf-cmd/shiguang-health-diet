// ShiguangFlutter/test/harness.dart
// 测试地基（M4-T1，M3 终审点名「提取共享测试辅助」）。
// 非 *_test.dart 后缀 → flutter test 不会把它当独立用例文件执行。
//
// 收敛的两件重复地基：
// ① RecordingAdapter —— M3 期间 test/data/contract_test.dart 与
//    test/data/health_api_report_test.dart 各抄了一份近乎相同的
//    HttpClientAdapter 实现（记 envelope + 可配响应）。新增组合根用例
//    （test/root_container_test.dart）还要「恒 500 + 计数」，第三份就不该再抄。
// ② useBigSurface —— 页尾卡落在 ListView 缓存区外时 find 不到，M3 用例靠
//    把视口拉到 500×1600 解决；setSurfaceSize + addTearDown 复位这段样板
//    在 weight_trend_test 里出现 3 次，收敛成一个 helper 并保证复位。
//
// 未收敛：test/auth_expiry_test.dart 的 _AlwaysExpiredAdapter / _Stub200Adapter
// —— 那是该场景专属的路由+门控桩（业务 401、续期端点 400、可挂起响应），
// 语义与通用 recorder 不同，硬塞进 harness 只会让两边都难读。
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/notifications/reminder_scheduler.dart';

/// 一条路由的桩响应：HTTP 状态码 + 响应体文本（ApiClient 自行解码，
/// 故 status 非 200 也能带业务 message，对齐 js/api.js:262 的取法）。
typedef StubResponse = ({int status, String text});

/// 记录请求并可配置响应的 dio 适配器。零网络。
///
/// 匹配键 [keyOf]：ApiClient 的所有业务请求都 POST 到同一个云函数入口，
/// 光看 URL 区分不出路由，故**优先取 envelope 的 `path` 字段**
/// （即契约路由名，如 `/diet/summary`），envelope 不存在时回落
/// `options.uri.path`（如续期端点 `/auth/v1/token`）。
///
/// 记录：[requests]（原始 RequestOptions）、[keys]（按上述规则解析出的路由键）、
/// [envelopes]（解出来的请求 envelope，供契约断言）。
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter({
    this.responseText = '{}',
    this.status = 200,
    Map<String, StubResponse> routes = const {},
    this.delay,
  }) : routes = Map.of(routes);

  /// 缺省响应体（可在用例中途改写，例如同一 adapter 回放不同 fixture）
  String responseText;

  /// 缺省 HTTP 状态码
  int status;

  /// 路由键 → 覆盖响应。例：`{'/auth/v1/token': (status: 400, text: '{}')}`
  final Map<String, StubResponse> routes;

  /// 非空 → 生成响应前先 await 它（模拟慢网/钉住 pending 态）。
  /// 参数为本次的路由键，便于只挂起某些路由。
  final Future<void> Function(String key)? delay;

  final List<RequestOptions> requests = [];
  final List<String> keys = [];
  final List<Map<String, dynamic>> envelopes = [];

  int get requestCount => requests.length;

  /// 某路由被请求了几次（未命中 routes 覆盖时的路由键同样计入）
  int countOf(String key) => keys.where((k) => k == key).length;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final raw = requestStream == null
        ? '{}'
        : utf8.decode(await requestStream.expand((c) => c).toList());
    final decoded = _tryDecodeMap(raw);
    envelopes.add(decoded ?? const <String, dynamic>{});
    final key = (decoded?['path'] as String?) ?? options.uri.path;
    keys.add(key);
    requests.add(options);
    if (delay != null) await delay!(key);
    final stub = routes[key];
    return ResponseBody.fromString(
      stub?.text ?? responseText,
      stub?.status ?? status,
      headers: {
        'content-type': ['application/json; charset=utf-8'],
      },
    );
  }

  Map<String, dynamic>? _tryDecodeMap(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void close({bool force = false}) {}
}

/// 把测试视口撑大：页尾卡片默认 800 高视口下会落在 ListView 缓存区之外，
/// find/geometry 取不到。内部登记 addTearDown 复位，用例不必各自记得收尾。
Future<void> useBigSurface(WidgetTester tester,
    {double w = 500, double h = 1600}) async {
  await tester.binding.setSurfaceSize(Size(w, h));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// 零动作通知端口：[NoopReminderScheduler] 覆写了 UI 会调到的全部方法，
/// 这里只需满足构造；一旦有用例真把调用漏到端口层，loud fail 好过静默触插件。
class NullNotificationPort implements NotificationPort {
  @override
  Future<void> init() async {}
  @override
  Future<void> periodDaily(
          {required int id,
          required int hour,
          required int minute,
          required String title,
          required String body}) async =>
      throw UnsupportedError('NullNotificationPort.periodDaily 不应被调用');
  @override
  Future<void> at(
          {required int id,
          required DateTime scheduledDate,
          required String title,
          required String body}) async =>
      throw UnsupportedError('NullNotificationPort.at 不应被调用');
  @override
  Future<void> show(
          {required int id,
          required String title,
          required String body}) async =>
      throw UnsupportedError('NullNotificationPort.show 不应被调用');
  @override
  Future<void> cancelAll() async =>
      throw UnsupportedError('NullNotificationPort.cancelAll 不应被调用');
}

/// no-op 提醒调度器（T8 缓办 B）：凡挂 ProfileScreen 的用例，initState 都会
/// 调 enabled()——不 override reminderSchedulerProvider 的话会真触
/// SharedPreferences 抛 MissingPluginException，被 initState 的 catchError
/// 静默吞掉：测试绿但走的是失败兜底路径，非确定。行为面测试
/// （profile_reminders_test）自带记录型 FakeScheduler，这里只服务"页面能挂
/// 起来"的基础用例。
class NoopReminderScheduler extends ReminderScheduler {
  NoopReminderScheduler({bool enabledValue = false})
      : _enabled = enabledValue,
        super(port: NullNotificationPort());

  bool _enabled;

  @override
  Future<bool> enabled() async => _enabled;

  @override
  Future<void> setEnabled(bool on) async => _enabled = on;

  @override
  Future<void> testMeal() async {}

  @override
  Future<void> testWater() async {}
}
