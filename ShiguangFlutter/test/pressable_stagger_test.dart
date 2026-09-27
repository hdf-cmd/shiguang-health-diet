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
    expect(op(), 1.0); // 不重播：initState 只跑一次 + late final _c/_fade 承载终值（同 tree 复用 State，_played 并不被再读）
  });
  testWidgets('Stagger 证伪钉（I-1）：delay 窗口摘挂仍播满 opacity=1；dispose 后定时器到点不炸', (tester) async {
    // deactivate→reactivate 的等价面。widget 测试无法让 Future.delayed 精确落在
    // 「元素 inactive 未 unmount」窗口（同帧末即定夺），故按任务口径用两钉替代：
    // ①index=2（delay 80ms）窗口内摘出再挂回、pump 过窗口，本体必须最终全显；
    // ②dispose 后到点 forward 被 _cDisposed 守卫静默挡掉（无 assert 异常）。
    Widget host(Widget body) => MaterialApp(home: Scaffold(body: body));
    const stagger = Stagger(index: 2, child: Text('x'));
    double op() => tester
        .widget<FadeTransition>(find.descendant(
            of: find.byType(Stagger), matching: find.byType(FadeTransition)))
        .opacity.value;

    // ① 半窗时 forward 未触发；摘出→挂回（新 State 重新计时），过窗后必须=1。
    await tester.pumpWidget(host(stagger));
    await tester.pump(const Duration(milliseconds: 40));
    expect(op(), 0.0); // delay 80ms 未到点，入场未启动
    await tester.pumpWidget(host(const SizedBox())); // 摘出：旧 State dispose，其挂起的 timer 由守卫挡掉
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpWidget(host(stagger)); // 挂回：新 State 照常承担播放
    await tester.pumpAndSettle();
    expect(op(), 1.0); // 永久 opacity 0 不可见 = 此钉红

    // ② 全新挂载后 delay 未到点即 dispose，再让时间过窗：定时器落锤不许抛。
    await tester.pumpWidget(host(const SizedBox())); // 先摘净
    await tester.pumpWidget(host(stagger)); // 全新 State 重挂，timer 从头挂起
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(host(const SizedBox())); // timer pending 中 dispose
    await tester.pumpAndSettle(); // pending timer 到点空转
    expect(tester.takeException(), isNull);
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
