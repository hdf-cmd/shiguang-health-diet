// ShiguangFlutter/lib/app/shell.dart
import 'package:flutter/material.dart';
import '../features/home/home_screen.dart';
// 三个占位文件同为 PlaceholderScreen，Dart 无法无名歧义导入，按 brief 同构文件结构加前缀区分。
import '../features/profile/profile_placeholder.dart' show PlaceholderScreen;
import '../features/record/record_placeholder.dart' as record_placeholder;
import '../features/report/report_placeholder.dart' as report_placeholder;
import 'theme.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  final _controller = PageController();
  int _index = 0;
  static const _tabs = ['首页', '记录', '报告', '我的'];

  void goToTab(int i) {
    setState(() => _index = i);
    _controller.animateToPage(i,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        children: const [
          HomeScreen(),
          record_placeholder.PlaceholderScreen('记录（M2 接入）'),
          report_placeholder.PlaceholderScreen('报告（M2 接入）'),
          PlaceholderScreen('我的（M2 接入）'),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.sp4, 0, Tokens.sp4, Tokens.sp3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.sp2, vertical: Tokens.sp2),
            decoration: BoxDecoration(
              color: Tokens.surfaceNav, // 白 92%（M1-I1：裸色值收敛进令牌）
              borderRadius: BorderRadius.circular(Tokens.radiusLg),
              boxShadow: Tokens.shadowFloat, // css --shadow-float 逐字镜像
            ),
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => goToTab(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: Tokens.sp2),
                        decoration: BoxDecoration(
                          color: _index == i ? Tokens.primarySoft : Colors.transparent,
                          borderRadius: BorderRadius.circular(Tokens.radiusMd),
                        ),
                        child: Text(_tabs[i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: Tokens.textSm,
                              fontWeight: _index == i ? FontWeight.w700 : FontWeight.w400,
                              color: _index == i ? Tokens.primaryDeep : Tokens.ink3,
                            )),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
