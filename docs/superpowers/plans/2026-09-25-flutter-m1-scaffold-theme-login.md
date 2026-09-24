# 食光 Flutter 重写 · M1（环境+骨架+主题+登录+静态首页）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭好 Flutter 工程基座：SDK 环境、分层骨架、设计令牌主题、登录页（静态校验版）、四 Tab 主框架、首页静态还原，并把 Flutter 纳入现有版本/CI 门禁。

**Architecture:** 单 package 分层 `domain/data/features/app`（M1 只建目录与触碰 app/features，domain 留空待 M2）；M1 零网络——登录提交只演示校验与占位反馈，真实接口在 M2 接入。

**Tech Stack:** Flutter 3.24.x stable / Dart 3.5+、flutter_test、GitHub Actions（subosito/flutter-action）。

**Spec:** `docs/superpowers/specs/2026-09-25-flutter-rewrite-design.md`（路线 A，M1 定义见其 §3）

## Global Constraints

- 工程目录：仓库根 `ShiguangFlutter/`；package 名 `shiguang_flutter`；org `com.healthydiet`；仅 Android 平台。
- Flutter 线版本从 **2.0.0** 起版：`pubspec.yaml` 固定 `version: 2.0.0+20000`，build 号规则 `major*10000 + minor*100 + patch`（与 H5 线 package.json 的 1.x 互不干涉）。
- H5 栈（`index.html`/`js`/`css`/`HealthyDiet`）**零改动**；api-diet 云函数零改动。
- 设计令牌唯一来源是 `css/design-tokens.css`，Dart 侧只做镜像，值必须逐字一致。
- 提交信息：简体中文、`type: 描述` 前缀（feat/fix/ci/docs/chore），与仓库现有风格一致。
- 国内网络：pub 与引擎下载走镜像环境变量 `PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`；git 推 GitHub 依赖 Clash（127.0.0.1:7897），推送前照例扫历史。
- 已知环境风险：本机工作区路径含中文（`C:\Desktop\健康饮食app`）。Gradle 构建已被 HealthyDiet 证明可行；若 `flutter create`/`flutter pub get` 报路径编码类错误，把**SDK 装在纯 ASCII 路径**（本计划默认 `C:\flutter`）即可绕开，工程位置不动。
- 环境实测（T2/T3 确认，全任务适用）：`flutter analyze` 在中文路径下必崩（flutter_tools UTF-16 bug）→ **静态分析一律 `dart analyze`**；`flutter test` 可直跑；程序化 shell 不继承 User PATH/镜像变量，每条命令先 `export PATH="$PATH:/c/flutter/bin"`。
- 每个任务结束即 commit；测试先行（先写失败测试→跑失败→实现→跑绿）。

---

### Task 1: 安装 Flutter SDK 并验证环境

**Files:**
- 无代码文件；产出可用 `flutter` 命令 + 本会话环境验证记录

- [ ] **Step 1: 用清华镜像 git 克隆 stable（浅克隆，约 200-400MB）**

```bash
git clone --depth 1 -b stable https://mirrors.tuna.tsinghua.edu.cn/git/flutter/flutter.git /c/flutter
```
Expected: 克隆完成，`/c/flutter/flutter` 存在。失败若是网络重置→开 Clash 重试（git 已配代理）。

- [ ] **Step 2: 配置 PATH 与镜像（当前用户级，不污染系统）**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH','User') + ';C:\flutter\bin', 'User'); [Environment]::SetEnvironmentVariable('PUB_HOSTED_URL','https://pub.flutter-io.cn','User'); [Environment]::SetEnvironmentVariable('FLUTTER_STORAGE_BASE_URL','https://storage.flutter-io.cn','User')"
```
同时把镜像变量注入当前 Bash 会话：
```bash
export PATH="$PATH:/c/flutter/bin" PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

- [ ] **Step 3: 首次运行拉入 Dart 工具链（下载引擎产物）**

```bash
flutter --version
```
Expected: 打印 `Flutter 3.24.x` 与 `Dart 3.5.x`（首跑会自行下载，慢网 5-15 分钟）。

- [ ] **Step 4: doctor 验证 Android 工具链**

```bash
flutter doctor
```
Expected: `[✓] Flutter`，`[✓] Android toolchain`（复用本机已有 SDK `C:\Users\24755\AppData\Local\Android\Sdk` 与 JDK17；若报 license 执行 `flutter doctor --android-licenses` 全 y）。`[✗] Visual Studio`/`Chrome` 等与 Android 无关项忽略。

- [ ] **Step 5: 记录版本到会话报告**

把 `flutter --version` 输出贴给用户，确认无阻塞后进 Task 2。

---

### Task 2: 脚手架工程与分层目录

**Files:**
- Create: `ShiguangFlutter/`（flutter create 生成，仅 android 平台）
- Create: `ShiguangFlutter/lib/app/`、`lib/domain/`、`lib/data/`、`lib/features/auth/`、`lib/features/home/`、`lib/features/record/`、`lib/features/report/`、`lib/features/profile/`、`lib/features/scale/`
- Create: `ShiguangFlutter/lib/domain/.gitkeep`、`lib/data/.gitkeep`（M2 才填充）
- Modify: `ShiguangFlutter/pubspec.yaml`（version/name/描述）
- Modify: 仓库根 `.gitignore`（追加 Flutter 产物）

**Interfaces:**
- Produces: 可 `flutter run` 的空壳工程；后续任务全部在 `lib/app|features` 下建文件

- [ ] **Step 1: 生成工程**

```bash
cd /c/Desktop/健康饮食app && flutter create --org com.healthydiet --project-name shiguang_flutter --platforms android ShiguangFlutter
```
Expected: `Done.`，`ShiguangFlutter/android` 存在。若中文路径报错→报告用户（见 Global Constraints 风险条），不要私自挪仓库位置。

- [ ] **Step 2: 建分层目录与占位**

```bash
cd ShiguangFlutter/lib && mkdir -p app domain data features/auth features/home features/record features/report features/profile features/scale && touch domain/.gitkeep data/.gitkeep
```

- [ ] **Step 3: 改 pubspec 版本与清理默认依赖**

`pubspec.yaml` 中 `version: 1.0.0+1` 改为 `version: 2.0.0+20000`；删除 `flutter_lints` 之外的模板注释块即可（M1 不加运行时依赖）。

- [ ] **Step 4: 根 .gitignore 追加**

```
# Flutter
ShiguangFlutter/.dart_tool/
ShiguangFlutter/build/
ShiguangFlutter/android/.gradle/
ShiguangFlutter/.flutter-plugins*
```

- [ ] **Step 5: 冒烟——analyze + test 必须绿（模板自带 widget_test 先删掉）**

```bash
cd ShiguangFlutter && rm test/widget_test.dart && flutter analyze && flutter test
```
Expected: `No issues found!`；`No test files found`（exit code 0 或提示无测试均可，不得有失败）。

- [ ] **Step 6: Commit**

```bash
cd /c/Desktop/健康饮食app && git add ShiguangFlutter .gitignore && git commit -m "feat: Flutter 工程脚手架——ShiguangFlutter 分层骨架（domain/data/features/app），2.0.0 起版"
```

---

### Task 3: 设计令牌 → ThemeData

**Files:**
- Create: `ShiguangFlutter/lib/app/theme.dart`
- Test: `ShiguangFlutter/test/theme_test.dart`

**Interfaces:**
- Produces: `Tokens`（颜色/圆角/间距常量类）、`shiguangTheme()` → ThemeData。Task 4/5/6 的界面只允许引用 Tokens。

- [ ] **Step 1: 写失败测试**

```dart
// ShiguangFlutter/test/theme_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart';

void main() {
  test('令牌与 css/design-tokens.css 逐字一致（抽查关键色）', () {
    expect(Tokens.bg.toARGB32(), 0xFFF4F5F0);
    expect(Tokens.primary.toARGB32(), 0xFF356B45);
    expect(Tokens.primaryDeep.toARGB32(), 0xFF234D30);
    expect(Tokens.ink.toARGB32(), 0xFF1C2418);
    expect(Tokens.warn.toARGB32(), 0xFFCE5F26);
    expect(Tokens.nutCarb.toARGB32(), 0xFFD99A34);
    expect(Tokens.radiusLg, 26.0);
    expect(Tokens.sp4, 16.0);
  });
  test('主题使用令牌作为 scaffold 背景与主色', () {
    final t = shiguangTheme();
    expect(t.scaffoldBackgroundColor, Tokens.bg);
    expect(t.colorScheme.primary, Tokens.primary);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd ShiguangFlutter && flutter test test/theme_test.dart
```
Expected: FAIL（找不到 `app/theme.dart`）。

- [ ] **Step 3: 实现 theme.dart**

```dart
// ShiguangFlutter/lib/app/theme.dart
import 'package:flutter/material.dart';

/// 食光设计令牌。唯一事实来源：仓库根 css/design-tokens.css，此文件为其 Dart 镜像，
/// 值必须逐字一致（theme_test 抽查把关）。
abstract class Tokens {
  // 色彩 · 中性
  static const bg = Color(0xFFF4F5F0);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFFBFCF9);
  static const surfaceSoft = Color(0xFFEDF1E8);
  static const ink = Color(0xFF1C2418);
  static const ink2 = Color(0xFF55624C);
  static const ink3 = Color(0xFF8E9B84);
  static const line = Color(0xFFE4E9DC);
  // 色彩 · 品牌
  static const primary = Color(0xFF356B45);
  static const primaryDeep = Color(0xFF234D30);
  static const primarySoft = Color(0xFFE3EFE0);
  // 色彩 · 营养素 / 语义
  static const nutCarb = Color(0xFFD99A34);
  static const nutProtein = Color(0xFFBF5B4B);
  static const nutFat = Color(0xFF5B8CA6);
  static const warn = Color(0xFFCE5F26);
  static const warnSoft = Color(0xFFF8E4D6);
  static const danger = Color(0xFFB23A2C);
  // 圆角
  static const radiusSm = 12.0;
  static const radiusMd = 18.0;
  static const radiusLg = 26.0;
  static const radiusSheet = 30.0;
  // 间距（4 基准）
  static const sp1 = 4.0, sp2 = 8.0, sp3 = 12.0, sp4 = 16.0;
  static const sp5 = 20.0, sp6 = 24.0, sp8 = 32.0;
  // 字号
  static const textXs = 11.0, textSm = 13.0, textMd = 15.0, textLg = 17.0;
  static const textXl = 24.0, textNum = 46.0;
}

ThemeData shiguangTheme() {
  final base = ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(
      seedColor: Tokens.primary, primary: Tokens.primary, surface: Tokens.surface));
  return base.copyWith(
    scaffoldBackgroundColor: Tokens.bg,
    textTheme: base.textTheme
        .apply(bodyColor: Tokens.ink, displayColor: Tokens.ink)
        .copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(
              fontSize: Tokens.textLg, fontWeight: FontWeight.w700),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: Tokens.textMd),
        ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Tokens.primaryDeep,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusSheet)),
        textStyle: const TextStyle(fontSize: Tokens.textMd, fontWeight: FontWeight.w700),
      )),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tokens.surface2,
      hintStyle: const TextStyle(color: Tokens.ink3, fontSize: Tokens.textSm),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: Tokens.sp4, vertical: Tokens.sp4),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          borderSide: const BorderSide(color: Tokens.line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          borderSide: const BorderSide(color: Tokens.line)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd ShiguangFlutter && flutter test test/theme_test.dart && flutter analyze
```
Expected: PASS ×2；No issues found。

- [ ] **Step 5: Commit**

```bash
git add ShiguangFlutter && git commit -m "feat: Flutter 设计令牌镜像与 ThemeData——值对齐 design-tokens.css，抽查入测"
```

---

### Task 4: 登录页（静态校验版）

**Files:**
- Create: `ShiguangFlutter/lib/features/auth/login_screen.dart`
- Create: `ShiguangFlutter/lib/main.dart`（替换模板：MaterialApp + shiguangTheme + LoginScreen）
- Test: `ShiguangFlutter/test/login_screen_test.dart`

**Interfaces:**
- Produces: `LoginScreen`（StatefulWidget）；`String? validateAuth({required bool isRegister, required String username, required String password})`（顶层函数，M2 真实登录复用同一校验）。提交成功路径 M1 用占位：`onSubmit` 回调为空实现时 SnackBar『M2 将接入真实登录』。

- [ ] **Step 1: 写失败测试**

```dart
// ShiguangFlutter/test/login_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/auth/login_screen.dart';

void main() {
  test('validateAuth：用户名空/密码<8 有报错，合法通过', () {
    expect(validateAuth(isRegister: false, username: '', password: '12345678'), '请输入用户名');
    expect(validateAuth(isRegister: false, username: 'uitest01', password: '1234567'),
        '密码至少 8 位');
    expect(validateAuth(isRegister: false, username: 'uitest01', password: 'Test1234!@'), isNull);
  });

  testWidgets('默认登录态；切注册改按钮文案', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LoginScreen()));
    // '登录' 同时是模式标签与提交按钮文案 → 两处
    expect(find.text('登录'), findsNWidgets(2));
    await tester.tap(find.text('注册'));
    await tester.pump();
    expect(find.text('注册并进入'), findsOneWidget);
  });

  testWidgets('空提交显示错误行', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LoginScreen()));
    await tester.tap(find.widgetWithText(FilledButton, '登录'));  // 点按钮，避开同名模式标签
    await tester.pump();
    expect(find.text('请输入用户名'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd ShiguangFlutter && flutter test test/login_screen_test.dart
```
Expected: FAIL（找不到 login_screen.dart）。

- [ ] **Step 3: 实现 login_screen.dart 与 main.dart**

```dart
// ShiguangFlutter/lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// M2 真实登录复用：返回 null 表示通过，否则为错误文案（与 H5 auth-error 行为一致）
String? validateAuth({required bool isRegister, required String username, required String password}) {
  if (username.trim().isEmpty) return '请输入用户名';
  if (password.length < 8) return '密码至少 8 位';
  return null;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onSubmit});
  /// M2 注入真实登录；M1 为空 → 提交通过校验后弹占位 SnackBar
  final Future<void> Function(String username, String password)? onSubmit;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isRegister = false;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _error;

  Future<void> _submit() async {
    final err = validateAuth(
        isRegister: _isRegister, username: _user.text, password: _pass.text);
    setState(() => _error = err);
    if (err != null) return;
    if (widget.onSubmit != null) {
      await widget.onSubmit!(_user.text.trim(), _pass.text);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('M2 将接入真实登录')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.sp5),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('食光', style: TextStyle(
              fontSize: 40, fontWeight: FontWeight.w800, color: Tokens.primaryDeep)),
          const SizedBox(height: Tokens.sp2),
          const Text('把每一餐，记成时光',
              style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2)),
          const SizedBox(height: Tokens.sp8),
          Container(
            padding: const EdgeInsets.all(Tokens.sp5),
            decoration: BoxDecoration(
              color: Tokens.surface,
              borderRadius: BorderRadius.circular(Tokens.radiusLg),
              boxShadow: const [BoxShadow(color: Color(0x141C2418), blurRadius: 28, offset: Offset(0, 10))],
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
                  onPressed: _submit,
                  child: Text(_isRegister ? '注册并进入' : '登录')),
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
              onTap: () => setState(() => _isRegister = reg),
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
```

```dart
// ShiguangFlutter/lib/main.dart（整文件替换模板）
import 'package:flutter/material.dart';
import 'app/theme.dart';
import 'features/auth/login_screen.dart';

void main() => runApp(const ShiguangApp());

class ShiguangApp extends StatelessWidget {
  const ShiguangApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '食光',
        theme: shiguangTheme(),
        home: const LoginScreen(),
      );
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd ShiguangFlutter && flutter test && flutter analyze
```
Expected: 全 PASS；No issues found。

- [ ] **Step 5: 模拟器目测（可选但推荐）**

```bash
flutter run -d medium_phone
```
对照 H5 登录页截图检查布局层级；看完 q 退出。

- [ ] **Step 6: Commit**

```bash
git add ShiguangFlutter && git commit -m "feat: Flutter 登录页——模式切换/校验/错误行，validateAuth 供 M2 复用"
```

---

### Task 5: 首页静态还原（今日盘子）

**Files:**
- Create: `ShiguangFlutter/lib/features/home/home_static_screen.dart`
- Test: `ShiguangFlutter/test/home_static_test.dart`

**Interfaces:**
- Produces: `HomeStaticScreen`（Task 5 已引用，M2 把内部数据换成 provider 驱动，类名不变）

- [ ] **Step 1: 写失败测试**

```dart
// ShiguangFlutter/test/home_static_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/home/home_static_screen.dart';

void main() {
  testWidgets('首页含标题"今日盘子"与三餐卡片', (tester) async {
    await tester.pumpWidget(MaterialApp(home: HomeStaticScreen()));
    expect(find.text('今日盘子'), findsOneWidget);
    expect(find.text('早餐'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('晚餐'), findsOneWidget);
    expect(find.text('0'), findsWidgets); // 热量环中心占位大数字
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd ShiguangFlutter && flutter test test/home_static_test.dart
```
Expected: FAIL（文件不存在）。

- [ ] **Step 3: 实现（静态卡片，M3 才画真环）**

```dart
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
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd ShiguangFlutter && flutter test && flutter analyze
```
Expected: 全 PASS。

- [ ] **Step 5: Commit**

```bash
git add ShiguangFlutter && git commit -m "feat: Flutter 首页静态还原——今日盘子标题/热量环占位卡/三餐行"
```

---

### Task 6: 主框架——悬浮胶囊 TabBar + PageView 四屏

**Files:**
- Create: `ShiguangFlutter/lib/app/shell.dart`
- Create: `ShiguangFlutter/lib/features/record/record_placeholder.dart`、`lib/features/report/report_placeholder.dart`、`lib/features/profile/profile_placeholder.dart`
- Modify: `ShiguangFlutter/lib/main.dart`（home 改 Shell；登录"成功"暂用占位按钮进 Shell 的 debug 入口）
- Test: `ShiguangFlutter/test/shell_test.dart`

**Interfaces:**
- Produces: `Shell`（IndexedStack+PageView 联动，`void goToTab(int)`）；`PlaceholderScreen(String title)`。M2 起 record/report/profile 逐个替换为真页面，Shell 签名不变。

- [ ] **Step 1: 写失败测试**

```dart
// ShiguangFlutter/test/shell_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/shell.dart';

void main() {
  testWidgets('默认首页 tab；点"我的"切到档案占位屏', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Shell()));
    expect(find.text('今日盘子'), findsOneWidget);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('我的（M2 接入）'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd ShiguangFlutter && flutter test test/shell_test.dart
```
Expected: FAIL（找不到 shell.dart）。

- [ ] **Step 3: 实现**

```dart
// ShiguangFlutter/lib/features/record/record_placeholder.dart（report/profile 同构，改 title）
import 'package:flutter/material.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Center(child: Text(title));
}
```

```dart
// ShiguangFlutter/lib/app/shell.dart
import 'package:flutter/material.dart';
import '../features/auth/login_screen.dart';
import '../features/home/home_static_screen.dart';
import '../features/profile/profile_placeholder.dart';
import '../features/record/record_placeholder.dart';
import '../features/report/report_placeholder.dart';
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
          HomeStaticScreen(),
          PlaceholderScreen('记录（M2 接入）'),
          PlaceholderScreen('报告（M2 接入）'),
          PlaceholderScreen('我的（M2 接入）'),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.sp4, 0, Tokens.sp4, Tokens.sp3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.sp2, vertical: Tokens.sp2),
            decoration: BoxDecoration(
              color: const Color(0xEBFFFFFF),  // 白 92%（3.24 无 withValues）
              borderRadius: BorderRadius.circular(Tokens.radiusLg),
              boxShadow: const [BoxShadow(
                  color: Color(0x421C2418), blurRadius: 44, offset: Offset(0, 14))],
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
```

`main.dart` 的 home 改为：`home: const Shell()`，并临时保留 `LoginScreen` 可达性——在 `ShiguangApp` 里用 `home: const Shell()` 即可（M2 再接登录门控；M1 目标是框架可见）。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd ShiguangFlutter && flutter test && flutter analyze
```
Expected: PASS；No issues found。

- [ ] **Step 5: Commit**

```bash
git add ShiguangFlutter && git commit -m "feat: Flutter 主框架——悬浮胶囊 TabBar + PageView 四屏联动（记录/报告/档案为 M2 占位）"
```

---

### Task 7: 门禁并轨——check:version 扩检 pubspec + CI flutter job

**Files:**
- Modify: `scripts/check-version.mjs`（追加 Flutter 线校验）
- Modify: `.github/workflows/ci.yml`（新增 flutter job）
- Modify: `README.md`（双栈说明一段）

**Interfaces:**
- Consumes: `ShiguangFlutter/pubspec.yaml` 的 `version: 2.0.0+20000`
- Produces: `npm run check:version` 同时守 H5（1.x）与 Flutter（2.x）两条线

- [ ] **Step 1: 改 check-version.mjs——在 problems 汇总前追加**

```js
/* Flutter 线（2.x）：pubspec.yaml 版本必须以 2. 开头，build 号 = major*10000+minor*100+patch */
const pubspec = read('ShiguangFlutter/pubspec.yaml');
const fv = pubspec.match(/^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)$/m);
if (!fv) {
  problems.push('ShiguangFlutter/pubspec.yaml 缺规范 version: X.Y.Z+N');
} else {
  const [_, M, m, p, n] = fv.map(Number);
  if (M !== 2) problems.push(`Flutter 线主版本应为 2，当前 ${M}`);
  const expect = M * 10000 + m * 100 + p;
  if (n !== expect) problems.push(`pubspec build 号 ${n} ≠ ${expect}（major*10000+minor*100+patch）`);
}
```

- [ ] **Step 2: 本地验证正反两向**

```bash
node scripts/check-version.mjs                       # 期望：一致，exit 0
sed -i 's/2.0.0+20000/2.0.0+1/' ShiguangFlutter/pubspec.yaml
node scripts/check-version.mjs; echo "exit=$?"       # 期望：报错，exit 1
sed -i 's/2.0.0+1/2.0.0+20000/' ShiguangFlutter/pubspec.yaml
node scripts/check-version.mjs                       # 期望：恢复，exit 0
```

- [ ] **Step 3: ci.yml 追加 flutter job**

```yaml
  flutter:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ShiguangFlutter
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.5'   # 执行时改为 Task 1 本机 flutter --version 实装版本（账本 Ruling 2）
          channel: 'stable'
          cache: true
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
```
同时把 lint-test job 里 `Version consistency` 步骤名不改（脚本内部已含双栈）。

- [ ] **Step 4: README 双栈段落**

在"当前版本"行下追加一行：
```markdown
**Flutter 线：开发中（2.0.0）** ｜ 工程在 `ShiguangFlutter/`，设计见 `docs/superpowers/specs/2026-09-25-flutter-rewrite-design.md`
```

- [ ] **Step 5: 全量回归 + Commit**

```bash
cd /c/Desktop/健康饮食app && npm run check:version && npm test && npm run lint
git add scripts/check-version.mjs .github/workflows/ci.yml README.md
git commit -m "ci: 门禁并轨——check:version 扩检 Flutter pubspec（2.x+build号），CI 增 flutter job，README 双栈声明"
```

---

## M1 完成定义（DoD）

1. `flutter test` 全绿（theme/login/shell/home 四组）；`flutter analyze` 零 issue；
2. 模拟器 `flutter run` 可见：登录页 →（M1 直接进）Shell 四 Tab 可滑可点、首页静态卡渲染；
3. `npm run check:version` 双栈校验通过（含故意改坏的负向验证）；
4. 提交 ≥5 个（每任务一个）；H5 栈文件零 diff（`git diff --stat HEAD~7 -- index.html js css HealthyDiet` 为空）；
5. 向老大演示 M1 效果并确认后进 M2 计划编写。
