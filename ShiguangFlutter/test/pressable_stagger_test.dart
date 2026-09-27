// ShiguangFlutter/test/pressable_stagger_test.dart
// M9-T5：PressableScale + Stagger 质感双件的行为钉。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/common/pressable.dart';
import 'package:shiguang_flutter/features/common/stagger.dart';

void main() {
  testWidgets('Stagger：首帧未播 opacity≈0，settle 后=1；同 tree 二次 pump 不重播', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Stagger(index: 0, child: Text('x')))));
    double op() => tester
        .widget<FadeTransition>(find.descendant(
            of: find.byType(Stagger), matching: find.byType(FadeTransition)))
        .opacity.value;
    expect(op(), lessThan(0.5)); // 入场前
    await tester.pumpAndSettle();
    expect(op(), 1.0);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Stagger(index: 0, child: Text('y'))))); // rebuild 同位
    await tester.pump();
    expect(op(), 1.0); // 不重播（State 复用，_played 生效）
  });
  testWidgets('PressableScale：按下 scale=0.975，松手 settle 回 1.0', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: PressableScale(onTap: () => taps++, child: const SizedBox(width: 100, height: 50)))));
    final center = tester.getCenter(find.byType(SizedBox).first);
    final g = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 150));
    expect(
        tester
            .widget<AnimatedScale>(find.descendant(
                of: find.byType(PressableScale), matching: find.byType(AnimatedScale)))
            .scale,
        0.975);
    await g.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(
        tester
            .widget<AnimatedScale>(find.descendant(
                of: find.byType(PressableScale), matching: find.byType(AnimatedScale)))
            .scale,
        1.0);
  });
}
