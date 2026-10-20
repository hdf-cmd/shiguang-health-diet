// ShiguangFlutter/test/ai_provider_sheet_test.dart
// M14-T5：「AI 识菜设置」弹层（我的 → AI 识菜设置）+ 配置透传到识菜请求。
// 判据（task-5-brief Step 1 + 控制者四条硬线）：
// ① 开关开 + 厂商 + 模型 + key → 保存落库；「清除」→ 存储清空、开关 false；
// ② 开关开但 key 为空 / 全空格 → 保存被拒（inline「请填写模型名与 API Key」），
//    不落库；
// ③ 设置页写明「配置不完整（缺模型或 Key）时仍走内置通道、会消耗内置每日次数」，
//    Key 说明与「换人使用请先清除」逐字在场；
// ④ 保存前 trim：模型名与 key 去首尾空白；
// ⑤ 切换厂商时模型重置：DeepSeek 回填 deepseek-flash，其余清空；
// ⑥ 已保存 key 时只占位显示「•••• 末4位」，不重填保存保留原 key；
// ⑦ 关闭开关保存不清 key（走内置、配置保留）；
// ⑧ 设置页保存的配置真的透传到 scanFood（StubHealthApi.lastScanProvider）——
//    桩必须记录 provider，否则本条恒绿；
// ⑨ 未配置 → scanFood 收到 null（回退内置通道）；
// ⑩ 我的页存在「AI 识菜设置」入口。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/auth_state.dart' show tokenStoreProvider;
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/ai_provider_store.dart';
import 'package:shiguang_flutter/data/token_store.dart' show InMemoryTokenStore;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/notifications/reminder_scheduler.dart'
    show reminderSchedulerProvider;
import 'package:shiguang_flutter/features/profile/ai_provider_sheet.dart'
    show openAiProviderSheet;
import 'package:shiguang_flutter/features/profile/profile_screen.dart'
    show ProfileScreen;
import 'package:shiguang_flutter/features/record/food_scan_sheet.dart'
    show openFoodScanFlow, scanImagePickProvider;

import 'harness.dart' show NoopReminderScheduler, useBigSurface;
import 'stubs/stub_health_api.dart';

/// 内存版自带配置存储（生产实现走 flutter_secure_storage，桌面测试不可用）。
class _MemStore implements AiProviderStore {
  _MemStore([this._value]);

  AiProviderConfig? _value;
  int saves = 0;
  int clears = 0;

  @override
  Future<AiProviderConfig?> load() async => _value;

  @override
  Future<void> save(AiProviderConfig config) async {
    saves++;
    _value = config;
  }

  @override
  Future<void> clear() async {
    clears++;
    _value = null;
  }
}

/// 宿主：两个入口各一枚钮——设置弹层走生产开层函数，识菜走生产全流程。
class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => openAiProviderSheet(context, ref),
                child: const Text('open-settings'),
              ),
              TextButton(
                onPressed: () => openFoodScanFlow(
                  context,
                  ref,
                  date: '2026-10-25',
                  meal: 'lunch',
                ),
                child: const Text('open-scan'),
              ),
            ],
          ),
        ),
      );
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required _MemStore store,
  StubHealthApi? api,
}) async {
  await useBigSurface(tester); // 弹层限高 78%，小视口下保存钮会滚出屏
  final container = ProviderContainer(
    overrides: [
      aiProviderStoreProvider.overrideWithValue(store),
      if (api != null) healthApiProvider.overrideWithValue(api),
      if (api != null)
        scanImagePickProvider.overrideWithValue(
            (_) async => (dataUrl: 'data:image/jpeg;base64,AAA', failure: null)),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: shiguangTheme(), home: const _Host()),
  ));
  await tester.pumpAndSettle();
}

/// 打开设置弹层（≙ 我的页入口点击后的形态）。
Future<void> _pumpSheet(WidgetTester tester, _MemStore store) async {
  await _pumpApp(tester, store: store);
  await tester.tap(find.text('open-settings'));
  await tester.pumpAndSettle();
  expect(find.text('AI 识菜设置'), findsOneWidget);
}

/// 读文本框当前文本（断言预填/重置/清空）。
String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

/// 选厂商（点触发器 → 点对话框选项）。
Future<void> _pickProvider(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const Key('ai-provider')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

/// 点遮罩关层（弹层限高 78%，左上角必在遮罩区）。
Future<void> _dismissSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
}

void main() {
  /* ---------- ① 保存 / 清除（brief Step 1 逐字） ---------- */

  testWidgets('保存：开关开 + 厂商 + 模型 + key → 落库；清除 → 开关关且清空',
      (tester) async {
    final store = _MemStore();
    await _pumpSheet(tester, store);
    await tester.tap(find.byKey(const Key('ai-switch')));
    await tester.tap(find.byKey(const Key('ai-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通义千问').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-model')), 'qwen-vl-max');
    await tester.enterText(find.byKey(const Key('ai-key')), 'sk-12345678');
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();
    final c = await store.load();
    expect(c!.enabled, isTrue);
    expect(c.id, 'qwen');
    expect(c.model, 'qwen-vl-max');
    expect(c.key, 'sk-12345678');

    await tester.tap(find.byKey(const Key('ai-clear')));
    await tester.pumpAndSettle();
    expect(await store.load(), isNull);
    // 「清除」= 开关置 false + 输入清空（brief Step 2）
    expect(
        tester.widget<Switch>(find.byKey(const Key('ai-switch'))).value, isFalse);
    expect(_fieldText(tester, 'ai-key'), isEmpty);
  });

  /* ---------- ② 不完整配置拒绝 ---------- */

  testWidgets('开关开但 key 为空 → 保存被拒，不落库', (tester) async {
    final store = _MemStore();
    await _pumpSheet(tester, store);
    await tester.tap(find.byKey(const Key('ai-switch')));
    await tester.enterText(find.byKey(const Key('ai-model')), 'm');
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pump();
    expect(await store.load(), isNull);
    expect(find.textContaining('请填写'), findsOneWidget);
  });

  testWidgets('key 全为空白（trim 后为空）→ 保存被拒，不落库', (tester) async {
    final store = _MemStore();
    await _pumpSheet(tester, store);
    await tester.tap(find.byKey(const Key('ai-switch')));
    await tester.enterText(find.byKey(const Key('ai-model')), 'm');
    await tester.enterText(find.byKey(const Key('ai-key')), '   ');
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pump();
    expect(await store.load(), isNull);
    expect(find.text('请填写模型名与 API Key'), findsOneWidget);
  });

  /* ---------- ③ 说明文案（控制者硬线 1） ---------- */

  testWidgets('设置页逐字写明：不完整仍走内置并消耗内置次数 + Key 说明 + 换人提示',
      (tester) async {
    await _pumpSheet(tester, _MemStore());
    expect(
        find.text('配置不完整（缺模型或 Key）时仍走内置通道、会消耗内置每日次数'),
        findsOneWidget);
    expect(find.text('Key 只存在本机加密存储；每次识别经你的服务器转发给厂商，不会保存。'),
        findsOneWidget);
    expect(find.text('换人使用请先清除'), findsOneWidget);
  });

  /* ---------- ④ 保存前 trim（控制者硬线 2） ---------- */

  testWidgets('保存前 trim：模型名与 key 去首尾空白后落库', (tester) async {
    final store = _MemStore();
    await _pumpSheet(tester, store);
    await tester.tap(find.byKey(const Key('ai-switch')));
    await _pickProvider(tester, '通义千问');
    await tester.enterText(find.byKey(const Key('ai-model')), '  qwen-vl-max  ');
    await tester.enterText(find.byKey(const Key('ai-key')), '  sk-12345678  ');
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();
    final c = await store.load();
    expect(c!.model, 'qwen-vl-max');
    expect(c.key, 'sk-12345678');
  });

  /* ---------- ⑤ 切换厂商重置模型（控制者硬线 3） ---------- */

  testWidgets('切换厂商时模型重置：DeepSeek 回填 deepseek-flash、其余清空',
      (tester) async {
    await _pumpSheet(tester, _MemStore());
    expect(_fieldText(tester, 'ai-model'), 'deepseek-flash', reason: 'DeepSeek 预填');

    await _pickProvider(tester, '通义千问');
    expect(_fieldText(tester, 'ai-model'), isEmpty, reason: '非 DeepSeek 清空手填');

    await tester.enterText(find.byKey(const Key('ai-model')), 'qwen-vl-max');
    await _pickProvider(tester, 'DeepSeek');
    expect(_fieldText(tester, 'ai-model'), 'deepseek-flash',
        reason: '切回 DeepSeek 回填默认名，不残留上一家型号');
  });

  /* ---------- ⑥ 已保存 key 的占位与保留 ---------- */

  testWidgets('已保存 key：占位只露末 4 位；不重填保存时保留原 key', (tester) async {
    final store = _MemStore(const AiProviderConfig(
        enabled: true,
        id: 'deepseek',
        model: 'deepseek-chat',
        key: 'sk-abcdef1234'));
    await _pumpSheet(tester, store);
    expect(
        tester.widget<Switch>(find.byKey(const Key('ai-switch'))).value, isTrue);
    expect(find.text('•••• 1234'), findsOneWidget, reason: '密文占位只露末 4 位');
    expect(_fieldText(tester, 'ai-key'), isEmpty, reason: '不把明文塞回输入框');

    await tester.enterText(find.byKey(const Key('ai-model')), 'deepseek-chat-v2');
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();
    final c = await store.load();
    expect(c!.model, 'deepseek-chat-v2');
    expect(c.key, 'sk-abcdef1234', reason: '未编辑 key = 保留原 key');
    expect(find.text('•••• 1234'), findsOneWidget, reason: '保存后仍只露末 4 位');
  });

  /* ---------- ⑦ 关闭开关不丢 key ---------- */

  testWidgets('关闭开关保存：走内置但不清除已存 key', (tester) async {
    final store = _MemStore(const AiProviderConfig(
        enabled: true,
        id: 'qwen',
        model: 'qwen-vl-max',
        key: 'sk-abcdef1234'));
    await _pumpSheet(tester, store);
    await tester.tap(find.byKey(const Key('ai-switch')));
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();
    final c = await store.load();
    expect(c!.enabled, isFalse);
    expect(c.key, 'sk-abcdef1234');
    expect(c.isUsable, isFalse, reason: '开关关 = 走内置，不带 provider');
  });

  /* ---------- ⑧ 配置透传到 scanFood（控制者硬线 4） ---------- */

  testWidgets('设置页保存的配置透传到 scanFood（id/model/key 全对）',
      (tester) async {
    final store = _MemStore();
    final api = StubHealthApi();
    await _pumpApp(tester, store: store, api: api);

    // 在设置页真实保存一份可用配置
    await tester.tap(find.text('open-settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-switch')));
    await _pickProvider(tester, '通义千问');
    await tester.enterText(find.byKey(const Key('ai-model')), 'qwen-vl-max');
    await tester.enterText(find.byKey(const Key('ai-key')), 'sk-12345678');
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();
    await _dismissSheet(tester);

    // 走一次识菜全流程
    await tester.tap(find.text('open-scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从相册选'));
    await tester.pumpAndSettle();

    expect(api.scanCalls, 1);
    final p = api.lastScanProvider;
    expect(p, isNotNull, reason: '桩必须记录 provider（否则本条恒绿）');
    expect(p!.enabled, isTrue);
    expect(p.id, 'qwen');
    expect(p.model, 'qwen-vl-max');
    expect(p.key, 'sk-12345678');
    expect(p.isUsable, isTrue, reason: '健康检查：可用配置才应随请求发出');
  });

  testWidgets('未配置 → scanFood 收到 null（回退内置通道）', (tester) async {
    final store = _MemStore();
    final api = StubHealthApi();
    await _pumpApp(tester, store: store, api: api);

    await tester.tap(find.text('open-scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从相册选'));
    await tester.pumpAndSettle();

    expect(api.scanCalls, 1);
    expect(api.lastScanProvider, isNull);
  });

  /* ---------- ⑩ 我的页入口 ---------- */

  testWidgets('我的页存在「AI 识菜设置」入口，点击开弹层', (tester) async {
    await useBigSurface(tester);
    final container = ProviderContainer(
      overrides: [
        healthApiProvider.overrideWithValue(StubHealthApi()),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
        aiProviderStoreProvider.overrideWithValue(_MemStore()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: shiguangTheme(), home: const ProfileScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-settings')), findsOneWidget);
    expect(find.text('AI 识菜设置'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-settings')));
    await tester.pumpAndSettle();
    expect(find.text('使用我自己的 Key'), findsOneWidget);
    expect(find.byKey(const Key('ai-switch')), findsOneWidget);
  });
}
