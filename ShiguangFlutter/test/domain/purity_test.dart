// ShiguangFlutter/test/domain/purity_test.dart
// 分层纯净性守卫：lib/domain/** 一律不得 import package:flutter
// （domain 必须可被纯 Dart 环境复用/单测，对齐 H5 logic.js「无 DOM、可被 node 直接 import」的定位）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/domain 下所有 .dart 不含 package:flutter 引用', () {
    final dir = Directory('lib/domain');
    expect(dir.existsSync(), isTrue,
        reason: 'flutter test 工作目录应为包根，实际 cwd=${Directory.current.path}');
    final dartFiles = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(dartFiles.isNotEmpty, isTrue);
    // 只匹配真实的 import/export 语句，避免文件头注释里的“不得 import package:flutter”误伤
    final importRe = RegExp(r'''^\s*(import|export)\s+["']package:flutter''');
    for (final f in dartFiles) {
      final hit = importRe.hasMatch(f.readAsStringSync());
      expect(hit, isFalse, reason: '${f.path} 违反 domain 分层铁律');
    }
  });
}
