// ShiguangFlutter/test/login_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/auth/login_screen.dart';

void main() {
  test('validateAuth：用户名空/密码<8 有报错，合法通过', () {
    expect(validateAuth(isRegister: false, username: '', password: '12345678'), '请输入用户名');
    expect(validateAuth(isRegister: false, username: 'uitest01', password: '1234567'),
        '密码至少 8 位');
    expect(validateAuth(isRegister: false, username: 'uitest01', password: 'Test1234!@'), isNull);
  });

  testWidgets('默认登录态；切注册改按钮文案', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LoginScreen()));
    // '登录' 同时是模式标签与提交按钮文案 → 两处
    expect(find.text('登录'), findsNWidgets(2));
    await tester.tap(find.text('注册'));
    await tester.pump();
    expect(find.text('注册并进入'), findsOneWidget);
  });

  testWidgets('空提交显示错误行', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LoginScreen()));
    await tester.tap(find.widgetWithText(FilledButton, '登录'));  // 点按钮，避开同名模式标签
    await tester.pump();
    expect(find.text('请输入用户名'), findsOneWidget);
  });
}
