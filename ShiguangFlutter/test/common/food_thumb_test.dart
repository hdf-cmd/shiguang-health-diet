// ShiguangFlutter/test/common/food_thumb_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/common/food_thumb.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

/// 1x1 合法 PNG（恒字节，非临时生成）
final _png1x1 = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

void main() {
  testWidgets('空 source → emoji 文本', (tester) async {
    await tester.pumpWidget(_wrap(const FoodThumb(source: '')));
    expect(find.text('🍽️'), findsOneWidget);
    await tester.pumpWidget(_wrap(const FoodThumb(source: null, emoji: '🍎')));
    expect(find.text('🍎'), findsOneWidget);
  });
  testWidgets('dataURL → Image.memory 渲染成功', (tester) async {
    final url = 'data:image/png;base64,${base64Encode(Uint8List.fromList(_png1x1))}';
    await tester.pumpWidget(_wrap(FoodThumb(source: url)));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('🍽️'), findsNothing);
  });
  testWidgets('坏 dataURL（非法 base64/非法图像）→ emoji 回退', (tester) async {
    await tester.pumpWidget(_wrap(const FoodThumb(source: 'data:image/png;base64!!!')));
    expect(find.text('🍽️'), findsOneWidget);
    await tester.pumpWidget(
        _wrap(const FoodThumb(source: 'data:image/png;base64,@@@')));
    expect(find.text('🍽️'), findsOneWidget);
  });
  testWidgets('非 data/http 前缀（脏值）→ emoji 回退，不抛', (tester) async {
    await tester.pumpWidget(_wrap(const FoodThumb(source: 'img/meals/x.jpg')));
    expect(find.text('🍽️'), findsOneWidget);
  });
}
