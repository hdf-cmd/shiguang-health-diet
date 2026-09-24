// ShiguangFlutter/test/shell_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/shell.dart';

void main() {
  testWidgets('默认首页 tab；点"我的"切到档案占位屏', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Shell()));
    expect(find.text('今日盘子'), findsOneWidget);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('我的（M2 接入）'), findsOneWidget);
  });
}
