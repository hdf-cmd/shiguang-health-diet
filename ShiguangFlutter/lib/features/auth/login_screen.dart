// ShiguangFlutter/lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;

/// 本地前置校验（与 H5 auth-error 行为一致）：返回 null 表示通过，否则为错误文案
String? validateAuth({required bool isRegister, required String username, required String password}) {
  if (username.trim().isEmpty) return '请输入用户名';
  if (password.length < 8) return '密码至少 8 位';
  return null;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onSubmit});
  /// M2 真实登录：由门控注入（register 模式先注册再登录，见 AuthNotifier.submit）；
  /// 上抛的 ApiException.message 显示到错误行。为空 → 占位 SnackBar（M1 兼容）。
  final Future<void> Function(String username, String password, bool isRegister)? onSubmit;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isRegister = false;
  bool _busy = false;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _error;

  Future<void> _submit() async {
    final err = validateAuth(
        isRegister: _isRegister, username: _user.text, password: _pass.text);
    setState(() => _error = err);
    if (err != null) return;
    if (widget.onSubmit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('M2 将接入真实登录')));
      return;
    }
    // H5 js/app.js:1901-1903：提交期间禁用按钮、文案改"请稍候…"
    setState(() => _busy = true);
    try {
      await widget.onSubmit!(_user.text.trim(), _pass.text, _isRegister);
      // 成功：门控置 authed 后本 widget 被 Shell 替换，无需自处理
    } on ApiException catch (e) {
      // H5 js/app.js:1921-1923：err.textContent = e.message || '操作失败'
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '操作失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.sp5),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('食光', style: TextStyle(
              fontSize: Tokens.textHero, fontWeight: FontWeight.w800, color: Tokens.primaryDeep)),
          const SizedBox(height: Tokens.sp2),
          const Text('把每一餐，记成时光',
              style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2)),
          const SizedBox(height: Tokens.sp8),
          Container(
            padding: const EdgeInsets.all(Tokens.sp5),
            decoration: BoxDecoration(
              color: Tokens.surface,
              borderRadius: BorderRadius.circular(Tokens.radiusLg),
              boxShadow: Tokens.shadowCard, // css --shadow-card 逐字镜像（M1-I1 收敛）
            ),
            child: Column(children: [
              _modeSwitch(),
              const SizedBox(height: Tokens.sp5),
              TextField(
                  controller: _user,
                  maxLength: 28,
                  decoration: const InputDecoration(
                      hintText: '用户名（中文/字母/数字/下划线）', counterText: '')),
              const SizedBox(height: Tokens.sp3),
              TextField(
                  controller: _pass,
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(hintText: '密码（至少 8 位）')),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Tokens.sp2),
                  child: Text(_error!,
                      style: const TextStyle(color: Tokens.danger, fontSize: Tokens.textSm)),
                ),
              const SizedBox(height: Tokens.sp4),
              FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy
                      ? '请稍候…'
                      : (_isRegister ? '注册并进入' : '登录'))),
            ]),
          ),
        ]),
      ))),
    );
  }

  Widget _modeSwitch() {
    return Container(
      padding: const EdgeInsets.all(Tokens.sp1),
      decoration: BoxDecoration(
          color: Tokens.surfaceSoft, borderRadius: BorderRadius.circular(Tokens.radiusMd)),
      child: Row(children: [
        for (final (label, reg) in [('登录', false), ('注册', true)])
          Expanded(
            child: GestureDetector(
              // H5 data-auth 点击会清错误行（js/app.js:1891）
              onTap: () => setState(() {
                _isRegister = reg;
                _error = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: Tokens.sp2),
                decoration: BoxDecoration(
                    color: _isRegister == reg ? Tokens.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(Tokens.radiusSm)),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: _isRegister == reg ? FontWeight.w700 : FontWeight.w400,
                        color: Tokens.ink)),
              ),
            ),
          ),
      ]),
    );
  }
}
