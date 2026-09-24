// ShiguangFlutter/lib/features/home/home_static_screen.dart
import 'package:flutter/material.dart';
import '../../app/theme.dart';

class HomeStaticScreen extends StatelessWidget {
  const HomeStaticScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Tokens.sp4),
        children: [
          const Text('今日盘子',
              style: TextStyle(
                  fontSize: Tokens.textXl, fontWeight: FontWeight.w800, color: Tokens.ink)),
          const SizedBox(height: Tokens.sp4),
          _card(
            color: Tokens.primaryDeep,
            child: const Row(children: [
              SizedBox(
                width: 120, height: 120,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox(width: 104, height: 104,
                      child: CircularProgressIndicator(
                          value: 0, strokeWidth: 10,
                          color: Colors.white38, backgroundColor: Colors.white12)),
                  Text('0', style: TextStyle(
                      fontSize: Tokens.textNum, color: Colors.white,
                      fontWeight: FontWeight.w800)),
                ]),
              ),
              SizedBox(width: Tokens.sp4),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('已摄入 / 目标', style: TextStyle(color: Colors.white70, fontSize: Tokens.textSm)),
                SizedBox(height: Tokens.sp1),
                Text('0 / 1975 kcal', style: TextStyle(color: Colors.white, fontSize: Tokens.textLg, fontWeight: FontWeight.w700)),
              ])),
            ]),
          ),
          const SizedBox(height: Tokens.sp3),
          _card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('三餐记录', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: Tokens.sp3),
              _MealRow(label: '早餐'), _MealRow(label: '午餐'), _MealRow(label: '晚餐'),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child, Color? color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Tokens.sp5),
      decoration: BoxDecoration(
        color: color ?? Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        boxShadow: const [BoxShadow(
            color: Color(0x141C2418), blurRadius: 28, offset: Offset(0, 10))],
      ),
      child: child,
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Tokens.sp2),
        child: Row(children: [
          Text(label, style: const TextStyle(color: Tokens.ink2, fontSize: Tokens.textSm)),
          const Spacer(),
          const Text('未记录',
              style: TextStyle(color: Tokens.ink3, fontSize: Tokens.textSm)),
        ]),
      );
}
