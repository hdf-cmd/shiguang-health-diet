// ShiguangFlutter/lib/features/common/eaten_badge.dart
// 行尾「吃过 N 次」徽标（M12-④）：我的食物库（自定义/内置）与记一笔搜索结果共用，
// 数据源是 foodFreqProvider 的全史计数。0 次不渲染——内置库几百道菜全挂
// 「吃过 0 次」只是噪声。
import 'package:flutter/material.dart';

import '../../app/theme.dart';

class EatenCountBadge extends StatelessWidget {
  const EatenCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.sp2, vertical: 2),
      decoration: BoxDecoration(
        color: Tokens.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '吃过 $count 次',
        style: const TextStyle(
          fontSize: Tokens.textXs,
          fontWeight: FontWeight.w600,
          color: Tokens.primaryDeep,
        ),
      ),
    );
  }
}
