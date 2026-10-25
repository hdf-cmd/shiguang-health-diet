// 常吃计数加载条：固定高度槽 + 呼吸胶囊，加载完成淡出但不改变布局。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/breathing_capsule.dart';
import 'food_freq.dart' show FreqStatus, foodFreqStatusProvider;

class FreqLoadingStrip extends ConsumerWidget {
  const FreqLoadingStrip({super.key, this.alignment = Alignment.centerLeft});

  final Alignment alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(foodFreqStatusProvider) == FreqStatus.loading;
    return SizedBox(
      height: 14,
      child: TickerMode(
        enabled: loading,
        child: AnimatedOpacity(
          opacity: loading ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Align(
            alignment: alignment,
            child: const BreathingCapsule(minWidth: 72, maxWidth: 150),
          ),
        ),
      ),
    );
  }
}
