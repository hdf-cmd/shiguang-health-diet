// ShiguangFlutter/lib/features/common/skeleton.dart
// M9-A2：公共骨架灰条（首页 _MealSkeletonRow 观感的通用化；纯静态不排
// 持续帧——pumpAndSettle 不死等，报告页 T4 骨架同路线）。
import 'package:flutter/material.dart';
import '../../app/theme.dart';

class SkeletonBar extends StatelessWidget {
  const SkeletonBar({super.key, this.width = double.infinity, this.height = 14});
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: Tokens.surfaceSoft,
            borderRadius: BorderRadius.all(Radius.circular(Tokens.radiusSm)),
          ),
        ),
      );
}
