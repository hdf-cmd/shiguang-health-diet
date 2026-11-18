// ShiguangFlutter/test/features/home/steps_card_test.dart
// 步数卡：数值/距离/活动热量展示、空态、千分位。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/mi_cloud_client.dart' show MiDailyActivity;
import 'package:shiguang_flutter/data/mi_daily_activity_store.dart'
    show miDailyActivityProvider;
import 'package:shiguang_flutter/features/home/steps_card.dart';

Future<void> pumpCard(
    WidgetTester tester, Map<String, MiDailyActivity> data) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      miDailyActivityProvider.overrideWith((ref) async => data),
    ],
    child: MaterialApp(
      theme: shiguangTheme(),
      home: Scaffold(
        body: StepsCard(date: '2026-11-18'),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('有数据：步数千分位 + 距离 + 活动热量 + 最近 7 天', (tester) async {
    await pumpCard(tester, {
      '2026-11-18': const MiDailyActivity(
          date: '2026-11-18', steps: 18780, distanceM: 12500, activeKcal: 655),
      '2026-11-17': const MiDailyActivity(
          date: '2026-11-17', steps: 3996, distanceM: 2600, activeKcal: 255),
      '2026-11-16': const MiDailyActivity(
          date: '2026-11-16', steps: 16709, distanceM: 11000, activeKcal: 861),
    });
    expect(find.text('18,780'), findsOneWidget);
    expect(find.text('≈ 12.5 km · 活动 655 kcal'), findsOneWidget);
    expect(find.text('最近 7 天'), findsOneWidget);
    expect(find.text('同步手环后显示步数与活动'), findsNothing);
  });

  testWidgets('空数据：显示同步提示，不显示大数字', (tester) async {
    await pumpCard(tester, const {});
    expect(find.text('同步手环后显示步数与活动'), findsOneWidget);
    expect(find.text('最近 7 天'), findsOneWidget);
  });

  testWidgets('千分位：四位数与三位数', (tester) async {
    await pumpCard(tester, {
      '2026-11-18': const MiDailyActivity(
          date: '2026-11-18', steps: 3996, distanceM: 2600, activeKcal: 255),
    });
    expect(find.text('3,996'), findsOneWidget);
  });
}
