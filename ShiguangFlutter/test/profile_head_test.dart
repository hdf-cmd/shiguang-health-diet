// ShiguangFlutter/test/profile_head_test.dart
// M5 Task 5：「我的」页资料卡头部（头像/昵称/签名）+ 编辑弹层。
// 行为权威源 H5（文案逐字）：
// - js/app.js:1004-1027 renderProfile —— 昵称/签名直填；无头像画
//   avatarText || nickname[0]（:1018，无「食」兜底；弹层预览才有 :1134 兜底）。
// - js/app.js:1137-1144 openProfileEdit —— 资料未加载（!p）点开为 no-op；
//   字段预填 nickname||'' / signature||''。
// - js/app.js:1153-1166 pe-save —— 昵称 trim 空 → 「昵称不能为空」；成功 →
//   PUT {nickname,signature} → 重取资料（invalidate ≙ :1159 getProfile+
//   renderProfile）→ 关弹层 → 「资料已保存」；ApiException → 「保存失败：msg」
//   其它 → 「保存失败：网络异常」（:1165 e.message||'网络异常'）。
// - js/app.js:1105-1119 handleAvatarPick —— 取消静默；tooLargeEncoded →
//   「图片仍过大，请换一张」(:1111)；readFailed → 「图片处理失败」(T3 新增面)；
//   上传成功 → 「头像已更新」(:1113) + 重取；失败 → 「头像上传失败：msg」
//   (:1117)。简报④把失败 toast 写成「保存失败：boom」，但 H5 :1117 是头像链
//   权威文案，按「文案逐字对齐 H5」总令取「头像上传失败：boom」——差异登记报告。
// 覆盖边界：image_picker 选择器不进 widget 测试——openProfileEditSheet 以
// AvatarPicker（顶层函数引用）注入 fake（简报 Step 1 ④）；真实「选图→压缩」链
// 留真机 T8 抽查。弹层保存链走 ProfileScreen 真实头部点击（默认 pickAvatar
// 只是引用，不触达即安全）。
// 装配样板：抄 test/profile_screen_test.dart 的 profileContainer
// （healthApi/tokenStore/scaleService/NoopReminderScheduler 全桩）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/auth_state.dart' show tokenStoreProvider;
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/data/token_store.dart';
import 'package:shiguang_flutter/features/common/image_pick.dart'
    show ImagePickFailure;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/notifications/reminder_scheduler.dart'
    show reminderSchedulerProvider;
import 'package:shiguang_flutter/features/profile/profile_edit_sheet.dart'
    show AvatarPicker, peNicknameFieldKey, peSignatureFieldKey, peSaveKey;
import 'package:shiguang_flutter/features/profile/profile_edit_sheet.dart'
    as sheet show openProfileEditSheet;
import 'package:shiguang_flutter/features/profile/profile_providers.dart'
    show profileProvider;
import 'package:shiguang_flutter/features/profile/profile_screen.dart'
    show ProfileScreen;
import 'package:shiguang_flutter/features/scale/scale_service.dart';

import 'harness.dart';
import 'scale_fakes.dart';
import 'stubs/stub_health_api.dart';

/// 简报①桩资料（fixture 契约键集，contract/fixtures/diet-core.json profile）
Map<String, dynamic> xiaomanProfile() => <String, dynamic>{
      'id': 'u_test',
      'nickname': '小满',
      'avatarText': '满',
      'avatarData': null,
      'signature': '把每一餐，记成时光',
      'goal': {'dailyKcal': 1679, 'targetWeight': 55, 'waterMl': 1600},
      'body': {
        'heightCm': 168, 'weightKg': 66.66, 'bmi': 23.6, 'age': 30,
        'gender': 'female', 'activity': 'moderate', 'deficit': 500,
      },
      'bodyUpdatedAt': 0,
    };

StubHealthApi newApi() => StubHealthApi(
      bodyMetrics: const <String, dynamic>{'weightKg': 66.66},
      profile: xiaomanProfile(),
    );

ProviderContainer headContainer(StubHealthApi api) {
  final container = ProviderContainer(
    overrides: [
      healthApiProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      scaleServiceProvider.overrideWithValue(fastScale()),
      reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  return container;
}

ScaleService fastScale() => ScaleService(
      FakeTransport(),
      scanTimeout: const Duration(milliseconds: 300),
      readTimeout: const Duration(milliseconds: 1500),
    );

Future<ProviderContainer> pumpProfile(WidgetTester tester, StubHealthApi api) async {
  await useBigSurface(tester);
  final container = headContainer(api);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    // 真主题必须上：目检抓到的 "BoxConstraints forces an infinite width"
    // （filledButtonTheme.minimumSize 宽=∞ × Row 非 flex 子）只有 shiguangTheme
    // 下才复现，默认 ThemeData 会漏。
    child: MaterialApp(theme: shiguangTheme(), home: ProfileScreen()),
  ));
  await tester.pumpAndSettle();
  return container;
}

/// ④专用宿主：不经 ProfileScreen 头部（其点击走默认 gallery 选择器=插件），
/// 直接以注入的 AvatarPicker 开弹层——选择器函数在测试里被 fake 替换。
class _EditSheetHost extends ConsumerWidget {
  const _EditSheetHost({required this.pick});
  final AvatarPicker pick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // watch 预取资料：openProfileEditSheet ≙ H5 :1138「!p 即 no-op」，
    // 不预取则点击时 value==null 弹层不开（no-op 语义由 ⑤ 的头部占位面旁证）。
    ref.watch(profileProvider);
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () =>
              sheet.openProfileEditSheet(context, ref, pickAvatar: pick),
          child: const Text('open-sheet'),
        ),
      ),
    );
  }
}

Future<void> pumpHost(WidgetTester tester, StubHealthApi api,
    {required AvatarPicker pick}) async {
  await useBigSurface(tester);
  final container = headContainer(api);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: shiguangTheme(), home: _EditSheetHost(pick: pick)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  /* ---------- ① 头部渲染（renderProfile :1004-1020） ---------- */

  testWidgets('①头部：昵称/签名直填；无头像画 avatarText「满」；「编辑 ›」在场',
      (tester) async {
    await pumpProfile(tester, newApi());

    expect(find.text('小满'), findsOneWidget); // :1005
    expect(find.text('把每一餐，记成时光'), findsOneWidget); // :1006
    expect(find.text('满'), findsOneWidget); // :1018 avatarText||nickname[0]
    expect(find.text('编辑 ›'), findsOneWidget); // index.html:185 逐字
  });

  testWidgets('①b 有 avatarData：画头像图（Image.memory），不再画首字',
      (tester) async {
    final api = newApi();
    // 1x1 PNG
    api.profile = {
      ...xiaomanProfile(),
      'avatarData':
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    };
    await pumpProfile(tester, api);

    expect(find.text('满'), findsNothing); // :1010 首字清空换 img
    expect(find.byType(Image), findsWidgets); // FoodThumb → Image.memory
  });

  /* ---------- ② 昵称闸（pe-save :1156） ---------- */

  testWidgets('②开弹层清空昵称→保存 → SnackBar「昵称不能为空」，updateProfile 0 次，弹层不关',
      (tester) async {
    final api = newApi();
    await pumpProfile(tester, api);

    await tester.tap(find.text('小满')); // #profile-head → openProfileEdit
    await tester.pumpAndSettle();
    expect(find.text('编辑资料'), findsOneWidget); // index.html:440 标题逐字
    expect(find.text('更换头像'), findsOneWidget); // :445 逐字
    // 预填（:1139-1140 nickname||'' / signature||''）
    expect(
        tester.widget<TextField>(find.byKey(peNicknameFieldKey)).controller!.text,
        '小满');
    expect(
        tester
            .widget<TextField>(find.byKey(peSignatureFieldKey))
            .controller!
            .text,
        '把每一餐，记成时光');

    await tester.enterText(find.byKey(peNicknameFieldKey), '   '); // trim 后空
    await tester.tap(find.byKey(peSaveKey));
    await tester.pumpAndSettle();

    expect(find.text('昵称不能为空'), findsOneWidget); // :1156 逐字
    expect(api.profileUpdateBodies, isEmpty); // 未发 PUT
    expect(find.byKey(peNicknameFieldKey), findsOneWidget); // 弹层未关
  });

  /* ---------- ③ 保存链（pe-save :1157-1163） ---------- */

  testWidgets('③改昵称+签名→保存：PUT body {nickname,signature}；重取 profile（GET+1）；toast「资料已保存」；弹层关；头部刷新',
      (tester) async {
    final api = newApi();
    await pumpProfile(tester, api);
    final getBefore = api.profileCalls;

    await tester.tap(find.text('小满'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(peNicknameFieldKey), '新昵称');
    await tester.enterText(find.byKey(peSignatureFieldKey), '新签名');
    await tester.tap(find.byKey(peSaveKey));
    await tester.pumpAndSettle();

    // PUT 契约体（HealthApi.updateProfile → /user/profile）
    expect(api.profileUpdateBodies, hasLength(1));
    expect(api.profileUpdateBodies.single,
        <String, dynamic>{'nickname': '新昵称', 'signature': '新签名'});
    // invalidate ≙ H5 :1159 重取（桩浅合并，重取回新值）
    expect(api.profileCalls, greaterThan(getBefore));
    expect(find.text('资料已保存'), findsOneWidget); // :1163 逐字
    expect(find.byKey(peNicknameFieldKey), findsNothing); // closeProfileEdit
    expect(find.text('新昵称'), findsOneWidget); // 头部重渲染
  });

  testWidgets('③b 保存失败：ApiException → 「保存失败：boom」，弹层不关；非 Api 异常 → 「保存失败：网络异常」',
      (tester) async {
    final api = newApi()..profileUpdateError = ApiException('boom');
    await pumpProfile(tester, api);

    await tester.tap(find.text('小满'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(peNicknameFieldKey), '改一下');
    await tester.tap(find.byKey(peSaveKey));
    await tester.pumpAndSettle();

    expect(find.text('保存失败：boom'), findsOneWidget); // :1165
    expect(find.byKey(peNicknameFieldKey), findsOneWidget); // 失败不关弹层

    api.profileUpdateError = ApiException(''); // message 空 → 网络异常兜底位
    await tester.tap(find.byKey(peSaveKey));
    await tester.pumpAndSettle();
    // ApiException('') 的 message 为空串：H5 `e.message || '网络异常'` falsy 兜底
    expect(find.text('保存失败：网络异常'), findsOneWidget);
  });

  /* ---------- ④ 头像链（handleAvatarPick :1105-1119，注入 fake 选择器） ---------- */

  /// 开弹层（pumpWidget 复用同型 MaterialApp/ScaffoldMessenger State，
  /// 清一遍 SnackBar 防上一用例的 toast 残留污染 findsNothing 断言）。
  Future<void> openSheet(WidgetTester tester, StubHealthApi api,
      {required AvatarPicker pick}) async {
    await pumpHost(tester, api, pick: pick);
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();
  }

  Future<void> tapChangeAvatar(WidgetTester tester) async {
    await tester.tap(find.text('更换头像'));
    await tester.pumpAndSettle();
  }

  testWidgets('④头像上传 500(message=boom) → toast「头像上传失败：boom」（H5 :1117），不重取',
      (tester) async {
    final api = newApi()..avatarError = ApiException('boom');
    await openSheet(tester, api, pick: () async =>
        (dataUrl: 'data:image/png;base64,AAAA', failure: null));
    final getBefore = api.profileCalls; // 弹层已加载完首取

    await tapChangeAvatar(tester);

    expect(api.avatarCalls, 1);
    expect(api.lastAvatarData, 'data:image/png;base64,AAAA');
    expect(find.text('头像上传失败：boom'), findsOneWidget);
    expect(api.profileCalls, getBefore); // 失败不 invalidate
  });

  testWidgets('④b 头像上传成功 → 「头像已更新」+ profileProvider 重取（GET+1）',
      (tester) async {
    final api = newApi();
    await openSheet(tester, api, pick: () async =>
        (dataUrl: 'data:image/png;base64,AAAA', failure: null));
    final getBefore = api.profileCalls;

    await tapChangeAvatar(tester);

    expect(api.avatarCalls, 1);
    expect(find.text('头像已更新'), findsOneWidget); // :1113 逐字
    expect(api.profileCalls, getBefore + 1); // :1114-1115 重取恰一次
  });

  testWidgets('④c 选择失败映射：tooLargeEncoded → 「图片仍过大，请换一张」；readFailed → 「图片处理失败」；取消静默——三种都不发 updateAvatar',
      (tester) async {
    for (final (failure, toast) in <(ImagePickFailure?, String?)>[
      (ImagePickFailure.tooLargeEncoded, '图片仍过大，请换一张'), // :1111 逐字
      (ImagePickFailure.readFailed, '图片处理失败'), // T3 新增文案
      (null, null), // 取消：dataUrl=null 且 failure=null → 静默
    ]) {
      final api = newApi();
      await openSheet(tester, api,
          pick: () async => (dataUrl: null, failure: failure));
      await tapChangeAvatar(tester);
      expect(api.avatarCalls, 0, reason: '$failure 不应触达上传');
      if (toast == null) {
        expect(find.byType(SnackBar), findsNothing);
      } else {
        expect(find.text(toast), findsOneWidget);
      }
      // 关弹层再进下一轮（不关：modal barrier 吸收下一轮 open-sheet 的点击）
      await tester.tap(find.text('✕'));
      await tester.pumpAndSettle();
    }
  });

  /* ---------- ⑤ 失败/加载占位（简报 Step 3：未登录信息 + 点击重试） ---------- */

  testWidgets('⑤getProfile 失败 → 头部「未登录信息」；清错后点头部 → invalidate 重试成功显昵称',
      (tester) async {
    final api = newApi()..profileError = ApiException('未登录');
    await pumpProfile(tester, api);

    expect(find.text('未登录信息'), findsOneWidget);
    expect(find.text('小满'), findsNothing);

    api.profileError = null;
    await tester.tap(find.text('未登录信息')); // 占位可点重试
    await tester.pumpAndSettle();

    expect(find.text('小满'), findsOneWidget); // 重取成功
    expect(api.profileCalls, 2); // 初次 1 次 + 重试 1 次
  });
}
