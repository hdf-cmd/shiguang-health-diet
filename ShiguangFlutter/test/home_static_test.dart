// ShiguangFlutter/test/home_static_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/home/home_static_screen.dart';

void main() {
  testWidgets('首页含标题"今日盘子"与三餐卡片', (tester) async {
    await tester.pumpWidget(MaterialApp(home: HomeStaticScreen()));
    expect(find.text('今日盘子'), findsOneWidget);
    expect(find.text('早餐'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('晚餐'), findsOneWidget);
    expect(find.text('0'), findsWidgets); // 热量环中心占位大数字
  });
}
