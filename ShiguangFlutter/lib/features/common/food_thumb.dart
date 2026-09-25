// ShiguangFlutter/lib/features/common/food_thumb.dart
// 列表缩略图（H5 .thumb 行为权威源：app.js:546 记录行 / :637 搜索行——
// ${f.image ? <img src=f.image> : f.emoji}）。Flutter 增强：解码/加载失败回退
// emoji（H5 坏图显示浏览器裂图，Flutter 回退更体面=R4 授权差异，报告登记）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

class FoodThumb extends StatelessWidget {
  const FoodThumb({
    super.key,
    required this.source,
    this.emoji = '🍽️',
    this.size = 40,
  });

  final String? source;
  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = source ?? '';
    final fallback = Text(emoji, style: TextStyle(fontSize: size * 0.55));
    if (s.isEmpty) return fallback;
    final Widget img;
    if (s.startsWith('data:')) {
      final comma = s.indexOf(',');
      if (comma < 0) return fallback;
      Uint8List bytes;
      try {
        bytes = Uint8List.fromList(base64Decode(s.substring(comma + 1)));
      } catch (_) {
        return fallback;
      }
      img = Image.memory(bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback);
    } else if (s.startsWith('http://') || s.startsWith('https://')) {
      img = Image.network(s,
          width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback);
    } else {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(Tokens.radiusSm),
      child: SizedBox(width: size, height: size, child: img),
    );
  }
}
