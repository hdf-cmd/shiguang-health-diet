// ShiguangFlutter/test/common/sheet_test.dart
// M9-T8 showShiguangSheet 收口钉（TDD 先行失败钉）：
// ① 三件套在场——顶部 drag handle（28×4 Container）、标题 Text 逐字、
//    ✕ 语义钮（bySemanticsLabel 前锚 ^关闭，弹层族定式）；
// ② 泛型返回透传——层内 Navigator.pop(value) 经 helper 原样带回；
// ③ ✕ 点按 = pop()，helper future 回 null（关层语义与各层原 ✕ 一致）；
// ④ 最大高 78%——ConstrainedBox maxHeight = 屏高×0.78；
// ⑤ closeKey 落 ✕ GestureDetector（各层 H5 同名键透传面）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiguang_flutter/features/common/sheet.dart';

/// 打开一层的最小宿主
Widget _host(Future<String?> Function(BuildContext) open) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('①三件套：handle 28×4 / 标题逐字 / ✕ 语义钮各一', (tester) async {
    await tester.pumpWidget(_host((ctx) =>
        showShiguangSheet<String>(ctx, title: '测试弹层标题', child: const SizedBox(height: 40))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // drag handle 钉：helper 里是 28×4 的 surfaceSoft 圆角 Container；
    // Container 的 width/height 参数不落公开字段（build 时合成
    // constraints），故按 decoration 色定位 + getSize 钉 28×4 实尺。
    final handle = find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).color == const Color(0xFFEDF1E8));
    expect(handle, findsOneWidget);
    // 28×16 = 4px 握把 + 上 sp2(8)/下 sp1(4) margin（Container 盒含 margin）
    expect(tester.getSize(handle), const Size(28, 16));
    expect(find.text('测试弹层标题'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp(r'^关闭')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('②泛型透传：层内 pop(value) 原样带回', (tester) async {
    String? result;
    await tester.pumpWidget(_host((ctx) => showShiguangSheet<String>(
          ctx,
          title: '透传层',
          child: Builder(builder: (sheetCtx) => TextButton(
                onPressed: () => Navigator.of(sheetCtx).pop('payload'),
                child: const Text('popme'),
              )),
        ).then((v) {
          result = v;
          return v;
        })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('popme'));
    await tester.pumpAndSettle();
    expect(result, 'payload');
    expect(find.text('透传层'), findsNothing);
  });

  testWidgets('③✕ 点按关层，future 回 null', (tester) async {
    String? result = 'untouched';
    await tester.pumpWidget(_host((ctx) => showShiguangSheet<String>(
        ctx, title: '关层钉', child: const SizedBox(height: 40)).then((v) {
      result = v;
      return v;
    })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('✕'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('关层钉'), findsNothing);
  });

  testWidgets('④最大高 78%：ConstrainedBox maxHeight=屏高×0.78', (tester) async {
    await tester.pumpWidget(_host((ctx) => showShiguangSheet<String>(
        ctx, title: '高度钉', child: const SizedBox(height: 40))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final size = MediaQuery.sizeOf(tester.element(find.text('open')));
    final box = tester.widget<ConstrainedBox>(find
        .ancestor(
            of: find.text('高度钉'),
            matching: find.byType(ConstrainedBox))
        .first);
    expect(box.constraints.maxHeight, closeTo(size.height * 0.78, 0.01));
  });

  testWidgets('⑤closeKey 透传到 ✕ GestureDetector', (tester) async {
    const key = Key('pin-close-key');
    await tester.pumpWidget(_host((ctx) => showShiguangSheet<String>(
        ctx, title: '键位钉', closeKey: key, child: const SizedBox(height: 40))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    expect(find.text('键位钉'), findsNothing); // 点键即关层
  });
}
