// M9-A1：SwrCache 会话级键值层单测（纯 Dart，无 Flutter 依赖）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/swr_cache.dart';

void main() {
  test('write/read 类型命中；异型读视为 miss', () {
    final c = SwrCache();
    c.write('k', 42);
    expect(c.read<int>('k'), 42);
    expect(c.read<String>('k'), isNull); // 类型不符=miss，不 ClassCast
    expect(c.read<int>('nope'), isNull);
  });
  test('invalidate 单键；invalidatePrefix 收族；clear 全清', () {
    final c = SwrCache()
      ..write('summary.2026-09-27', 1)
      ..write('summary.2026-09-26', 2)
      ..write('records.2026-09-27', 3);
    c.invalidate('records.2026-09-27');
    expect(c.read<int>('records.2026-09-27'), isNull);
    c.invalidatePrefix('summary.');
    expect(c.read<int>('summary.2026-09-27'), isNull);
    c.write('a', 1);
    c.clear();
    expect(c.read<int>('a'), isNull);
  });
}
