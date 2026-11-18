// ShiguangFlutter/test/features/band_sync/mi_import_store_test.dart
// 导入去重账本用例：去重、顺序保留、上限淘汰（SharedPreferences mock）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_flutter/features/band_sync/mi_import_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('空账本返回空集合', () async {
    final store = MiImportStore();
    expect(await store.load(), isEmpty);
  });

  test('addAll 去重且新 id 排在尾部', () async {
    final store = MiImportStore();
    await store.addAll(['mi:a', 'mi:b']);
    await store.addAll(['mi:b', 'mi:c']);
    final p = await SharedPreferences.getInstance();
    expect(p.getStringList(bandImportedIdsPrefKey), ['mi:a', 'mi:b', 'mi:c']);
  });

  test('超上限后淘汰最老的键', () async {
    final store = MiImportStore();
    final ids = List.generate(bandImportedIdsMax + 3, (i) => 'mi:$i');
    await store.addAll(ids);
    final loaded = (await SharedPreferences.getInstance())
        .getStringList(bandImportedIdsPrefKey)!;
    expect(loaded, hasLength(bandImportedIdsMax));
    expect(loaded.first, 'mi:3');
    expect(loaded.last, 'mi:${ids.length - 1}');
  });
}
