// ShiguangFlutter/test/domain/purity_test.dart
// 分层纯净性守卫：lib/domain/** 一律不得 import package:flutter
// （domain 必须可被纯 Dart 环境复用/单测，对齐 H5 logic.js「无 DOM、可被 node 直接 import」的定位）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 纯函数：扫描 Dart 源码文本，返回其中真实的 package:flutter import/export 违规行。
/// 逐行匹配且行首锚定 `import|export`——旧版正则未加 multiLine，`^` 只能匹配文件首字符，
/// 而 domain 文件均以注释开头，导致守卫恒真形同虚设（评审 Critical）。
/// 注释行（以 `//` 开头）不会误伤。
List<String> findFlutterImports(String source) {
  final importRe = RegExp(r'''^\s*(import|export)\s+["']package:flutter''');
  final hits = <String>[];
  for (final line in source.split('\n')) {
    if (importRe.hasMatch(line)) hits.add(line.trim());
  }
  return hits;
}

void main() {
  group('守卫自证（注入违规必红）', () {
    test('前置注释行 + flutter import 的样本能被抓到', () {
      const sample = '''
// 头部注释：分层铁律——本文件不得 import package:flutter。
// 第二行注释
import 'dart:convert';
import 'package:flutter/material.dart';

void main() {}
''';
      final hits = findFlutterImports(sample);
      expect(hits, hasLength(1));
      expect(hits.single, contains('package:flutter'));
    });

    test('export package:flutter 同样被抓到', () {
      const sample = '''
// 注释开头
export 'package:flutter/services.dart';
''';
      expect(findFlutterImports(sample), hasLength(1));
    });

    test('干净 domain 样本（含提及 import 的注释）不误报', () {
      const sample = '''
// 分层铁律：本文件不得 import package:flutter。
import 'dart:math' as math;

int jsRound(num x) => (x + 0.5).floor();
''';
      expect(findFlutterImports(sample), isEmpty);
    });
  });

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
    for (final f in dartFiles) {
      final hits = findFlutterImports(f.readAsStringSync());
      expect(hits, isEmpty, reason: '${f.path} 违反 domain 分层铁律：$hits');
    }
  });
}
