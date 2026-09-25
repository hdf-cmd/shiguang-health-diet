// ShiguangFlutter/lib/app/shell.dart
import 'package:flutter/material.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/record/record_screen.dart';
// M3-T4：报告 tab 接真实 ReportScreen；报告占位文件已删。M4-T4：我的 tab
// 接真实 ProfileScreen（体重卡+登出），profile_placeholder.dart 随之删除。
import '../features/report/report_screen.dart';
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

  /// 仅供测试断言 dispose 后不再被使用（M1 遗留核销）。
  @visibleForTesting
  PageController get debugPageController => _controller;

  @override
  void dispose() {
    _controller.dispose(); // M1 遗留：PageController 必须随 State 释放
    super.dispose();
  }

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
          RecordScreen(),
          ReportScreen(),
          ProfileScreen(),
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
