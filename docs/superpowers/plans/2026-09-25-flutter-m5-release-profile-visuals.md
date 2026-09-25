# M5 签名发布线 + 个人信息 + 食物图片 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flutter 端产出可日常安装的签名 release 包（食光名称/图标），并与 H5 信息面齐平：资料卡（头像/昵称/签名）、身体参数卡（五档+目标联动）、食物缩略图、自定义食物表单（含选图上传）。

**Architecture:** 延续 M1-M4 分层（domain 纯函数 / data HealthApi / features UI + Riverpod）。新增三块公共地基：`data_url.dart`（bytes→dataURL+大小闸）、`image_pick.dart`（image_picker 选图+原生压缩参数即 H5 compressAvatar 等价）、`food_thumb.dart`（有图画图/无图回退 emoji）。资料与身体参数收敛到一个 `profileProvider`（GET /user/profile 本就带 body/goal/avatar），保存链 bug-for-bug 复刻 H5「updateProfile → 目标 suggest 变化则 setGoal」。

**Tech Stack:** Flutter 3.47.5 / Riverpod 3.4.3 / image_picker（新增，唯一新运行时依赖）/ keytool+Gradle signingConfig。

**Spec:** `docs/superpowers/specs/2026-09-25-flutter-m5-release-profile-visuals-design.md`（本计划依据，执行时两份都读）

## Global Constraints

- **云函数 api-diet 一行不改**（硬约束）；写云端只走既有路由：`PUT /user/profile`、`PUT /user/goal`、`PUT /user/avatar`、`POST /foods/custom`（js/api.js:62-80）。
- 分层铁律：`lib/domain/` 不得 import package:flutter；UI 测试须显式 `import 'package:flutter/material.dart';`。
- 分析/测试命令：`dart analyze lib test`（**永不** `flutter analyze`）；`flutter test`；每条 Bash 先 `export PATH="$PATH:/c/flutter/bin"` + `export PUB_HOSTED_URL=https://pub.flutter-io.cn` + `export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`；构建判成败看 `$?` 或产物存在性，禁管道吞退出码。
- 数据行为 bug-for-bug 对齐 H5（文案/toast/校验闸/请求体逐字）；**R4 授权**：视觉与交互层可 Flutter 创新，偏离处在报告登记「差异+理由」；**每任务收尾开模拟器目检**（`flutter emulators --launch medium_phone`，adb 坑见下）。
- adb：`$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe`；**绝不 adb kill-server**；截图坐标×1.2；输入前切 LatinIME（`adb shell ime set com.android.inputmethod.latin/.LatinIME`）。
- 版本：任务内不动版本；T8 统一升 **2.3.0+20300**（build=2*10000+3*100+0）。H5 线（1.4.0）零改动，`node --test` 须零 diff 全绿。
- keystore/密码**绝不进 git**：`ShiguangFlutter/.gitignore` 加 `android/key.properties`、`android/*.jks`；密码仅在任务输出里出现一次，由老大当场备份。
- 互通红线：测试夹具只用 u_test/rec_test_*/uitest01 系样本；真实 uid、真实凭证不进任何测试与代码。
- 提交信息中文，格式延续 `feat: M5-T<N> …` / `fix: …` / `build: …`；每任务一提交（含测试），T8 收官单独提交版本+APK。

---

## 现状锚点（执行前必读，均为已核实事实）

- `ShiguangFlutter/lib/data/health_api.dart`：已有 getProfile(:24)/getBodyMetrics(:29)/logWeight(:34)/addFoodRecord(:56)/searchFoods(:77)；**无** updateProfile/setGoal/updateAvatar/addCustomFood。
- `contract/fixtures/diet-core.json`：13 条路由，`profile`（GET，responseFields 已含 body/goal/avatarData）与 `logWeight` 等条目形状即模板；`ShiguangFlutter/test/data/contract_test.dart` 按 `dartMethod` switch 派发（:85-110），新 dartMethod 须加 case。
- `ShiguangFlutter/lib/features/profile/profile_screen.dart`：`profileWeightProvider`(:38)、`_weightCard`(:296)、`_remindCard`(:408)、build 的 ListView 顺序=标题→体重卡→提醒卡→退出(:278-281)。SnackBar 惯例 `_toast`(:166)。
- `ShiguangFlutter/lib/features/record/search_sheet.dart`：结果行 emoji 位在 :265 附近（`Text('${f['emoji'] ?? '🍽️'}'…)`），空结果文案区 :222（「换个说法，或添加自定义食物」——H5 此处下方有「＋ 自定义食物」按钮，Flutter 未落）。
- `ShiguangFlutter/test/harness.dart`：RecordingAdapter（routes/keys/countOf/envelopes）、useBigSurface、NoopReminderScheduler。新页测试的 profileContainer 样板抄 `test/profile_screen_test.dart`。
- `ShiguangFlutter/lib/domain/`：`models.dart Body`（六字段+fromMap 默认值）、`metabolism.dart computeMetabolism(Body, double? targetWeight, [Map? actualInfo, DateTime? now]) → MetabResult{bmr,tdee,suggest,…}`、`constants.dart activity`（五档 label）/`bodyDefault`、`js_compat.dart jsRound/jsFixed1/jsNumText`。
- H5 行为权威源：资料编辑弹层 app.js:1140-1166（昵称闸/「资料已保存」/「保存失败：」）、头像压缩 app.js:1085-1116（256 长边/q0.82/5MB 闸/280000 字符闸/「头像已更新」）、自定义食物 app.js:1168-1276（cf 全表单+「已存入食物库，搜索可用」+「已记入X · 名」）、身体卡+弹层 app.js:1572-1700（步进/归一闸 100-250/30-200/10-100、「身体档案已保存」、失败「已本地保存：」、deficit 档 300/500/750）、缩略图渲染位 app.js:546（记录行）与 :637（搜索结果行）、syncTarget app.js:1701-1719。
- Android 壳：`ShiguangFlutter/android/app/build.gradle.kts` release 现用 debug 签名(:37-43)；manifest `android:label="shiguang_flutter"`(:24)；mipmap 只有模板 PNG（无 anydpi-v26）。H5 图标=adaptive 矢量：`HealthyDiet/app/src/main/res/drawable/ic_launcher_foreground.xml` + `mipmap-anydpi-v26/ic_launcher.xml`（background 色 `#2E7D32`，values/colors.xml:10）。

---

### Task 1: 签名发布线——keystore、signingConfig、应用名与食光图标

**Files:**
- Create: `ShiguangFlutter/android/key.properties`（**不入库**）、`ShiguangFlutter/android/shiguang-flutter-release.jks`（**不入库**）
- Modify: `ShiguangFlutter/.gitignore`（追加两行）
- Modify: `ShiguangFlutter/android/app/build.gradle.kts`（:37-43 release 块 + 顶部读 properties）
- Modify: `ShiguangFlutter/android/app/src/main/AndroidManifest.xml:24`（label→食光）
- Create: `ShiguangFlutter/android/app/src/main/res/drawable/ic_launcher_foreground.xml`（原样复制 H5 版）
- Create: `ShiguangFlutter/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- Modify: `ShiguangFlutter/android/app/src/main/res/values/colors.xml`（新建或追加 `ic_launcher_background` = `#2E7D32`）

**Interfaces:**
- Produces: 可安装的签名 release 构建链；T8 直接 `flutter build apk --release --split-per-abi` 出正式包。key.properties 缺失时回退 debug 签名（他人 clone/CI 不断构建）。

- [ ] **Step 1: 生成密码与 keystore**

```bash
cd ShiguangFlutter/android
PWD1=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)   # 20 位随机强密码
keytool -genkeypair -v -keystore shiguang-flutter-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias shiguang-flutter \
  -storepass "$PWD1" -keypass "$PWD1" \
  -dname "CN=Shiguang, OU=App, O=Shiguang, L=Beijing, ST=Beijing, C=CN"
printf 'storePassword=%s\nkeyPassword=%s\nkeyAlias=shiguang-flutter\nstoreFile=shiguang-flutter-release.jks\n' "$PWD1" "$PWD1" > key.properties
echo "===== 把下面这行密码原样回显给老大备份，本会话不留副本 ====="; echo "$PWD1"
```

注意：keytool 用 Android Studio JBR 或 Adoptium 17 的（`"C:/Program Files/Eclipse Adoptium/jdk-17.0.20.101-hotspot/bin/keytool.exe"` 若 PATH 无 keytool）。密码会出现在终端输出——这是唯一一次，属交付内容（老大备份），不写进任何文件/提交。

- [ ] **Step 2: gitignore 两行 + 验证不入库**

`ShiguangFlutter/.gitignore` 末尾追加：

```
android/key.properties
android/*.jks
```

验证：`git status --short` 里不得出现 key.properties / .jks；`git check-ignore -v android/key.properties` 有命中行。

- [ ] **Step 3: build.gradle.kts 签名配置**

文件顶部（`plugins {}` 之前）加：

```kotlin
import java.util.Properties
import java.io.FileInputStream
```

`android { }` 内 `buildTypes` 之前加：

```kotlin
    // M5-T1：release 签名读 android/key.properties（该文件与 *.jks 均 git-ignore）。
    // 缺失时回退 debug 签名——他人 clone/CI 无密钥也能 assembleRelease（非交付包）。
    val keystoreProperties = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null
        && file(keystoreProperties.getProperty("storeFile")).exists()

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }
```

`buildTypes.release` 块把 `signingConfig = signingConfigs.getByName("debug")` 替换为：

```kotlin
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug") // 回退语义见上
            }
```

（删掉模板两行 TODO 注释。）

- [ ] **Step 4: 应用名与图标资源**

`AndroidManifest.xml:24` → `android:label="食光"`。复制 H5 前景矢量并新建自适应图标三件：

```bash
cp ../HealthyDiet/app/src/main/res/drawable/ic_launcher_foreground.xml \
   ShiguangFlutter/android/app/src/main/res/drawable/ic_launcher_foreground.xml
mkdir -p ShiguangFlutter/android/app/src/main/res/mipmap-anydpi-v26
```

`mipmap-anydpi-v26/ic_launcher.xml`（与 H5 版逐字）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
```

`res/values/colors.xml` 新建（Flutter 模板原无此文件；若已存在则只追加 item）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#2E7D32</color>
</resources>
```

**登记降级面**：模板 `mipmap-*/ic_launcher.png`（Flutter logo）**保留不删**——API 24/25 设备会看到 Flutter 默认图标，API 26+ 由 anydpi-v26 覆盖为食光自适应图标。理由：aapt 要求 @mipmap/ic_launcher 有全配置兜底；老大与模拟器均 API 33+，10 年前机型面不值得引入栅格化工具链。报告里写明。

- [ ] **Step 5: release 构建验证（不接管道，判真实退出码）**

```bash
export PATH="$PATH:/c/flutter/bin"
export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
cd ShiguangFlutter && flutter build apk --release --split-per-abi > ../.mimosa/m5t1-build.log 2>&1; echo "exit=$?"
ls -la build/app/outputs/flutter-apk/   # 期望 app-arm64-v8a-release.apk 与 app-x86_64-release.apk，mtime 晚于本轮
```

预期首跑 gradle 增量约 3-8 分钟（NDK/依赖 M4 已缓存）。exit≠0 时读日志尾部 50 行归因，禁盲目重试。

- [ ] **Step 6: 验签 + 模拟器目检图标/名称（R4）**

```bash
"$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" install -r \
  ShiguangFlutter/build/app/outputs/flutter-apk/app-x86_64-release.apk
```

（模拟器未在线先 `flutter emulators --launch medium_phone` 等 boot complete。）验三点：①能装能开（release 无 flutter 右上角徽标）；②桌面图标=食光绿底图标、名称=食光（`adb shell cmd package list packages -f com.healthydiet.shiguang_flutter` 排重后可用桌面截图目检：`adb shell input keyevent KEYCODE_HOME` + 截图）；③`dart analyze lib test` 无涉（本任务零 Dart 码），跑 `flutter test` 确认 302 全绿不回归。

- [ ] **Step 7: Commit**

```bash
git add ShiguangFlutter/.gitignore ShiguangFlutter/android/app/build.gradle.kts \
  ShiguangFlutter/android/app/src/main/AndroidManifest.xml \
  ShiguangFlutter/android/app/src/main/res/drawable/ic_launcher_foreground.xml \
  ShiguangFlutter/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml \
  ShiguangFlutter/android/app/src/main/res/values/colors.xml
git commit -m "build: M5-T1 签名发布线——独立 keystore+key.properties(均不入库,缺失回退debug)+应用名食光+H5自适应图标移植"
```

提交后 `git show --stat HEAD` 复核**没有** key.properties/jks 混入。

---

### Task 2: HealthApi 四条新路由 + 契约 fixture 双端锁定

**Files:**
- Modify: `ShiguangFlutter/lib/data/health_api.dart`（用户段追加 3 法 + 食物库段追加 addCustomFood）
- Modify: `contract/fixtures/diet-core.json`（routes 追加 4 条）
- Modify: `ShiguangFlutter/test/data/contract_test.dart`（invoke switch 加 4 case）
- Modify: `tests/contract.test.js`（若其按 jsMethod switch 派发则补 4 条；按 fixture 泛化循环则零改动——先读再动）

**Interfaces:**
- Produces（T5/T6/T7 消费，签名逐字）：
  - `Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data)` → `PUT /user/profile`，body=data 原样；
  - `Future<Map<String, dynamic>> setGoal(num dailyKcal, num targetWeight)` → `PUT /user/goal`，body `{'dailyKcal':…,'targetWeight':…}`；
  - `Future<Map<String, dynamic>> updateAvatar(String dataUrl)` → `PUT /user/avatar`，body `{'data':…}`；
  - `Future<Map<String, dynamic>> addCustomFood(Map<String, dynamic> food)` → `POST /foods/custom`，body 原样。

- [ ] **Step 1: 写失败契约测试**

`contract/fixtures/diet-core.json` 的 `routes` 末尾追加（形状对齐现有条目；requestSample 即契约断言源）：

```json
{
  "route": "updateProfile", "dartMethod": "updateProfile", "jsMethod": "updateProfile",
  "path": "/user/profile", "httpMethod": "PUT", "readOnly": false,
  "requestSample": { "body": { "nickname": "小满", "signature": "把每一餐，记成时光" } },
  "responseShape": "object", "responseFields": ["ok"]
},
{
  "route": "setGoal", "dartMethod": "setGoal", "jsMethod": "setGoal",
  "path": "/user/goal", "httpMethod": "PUT", "readOnly": false,
  "requestSample": { "body": { "dailyKcal": 1679, "targetWeight": 55 } },
  "responseShape": "object", "responseFields": ["ok"]
},
{
  "route": "avatar", "dartMethod": "updateAvatar", "jsMethod": "updateAvatar",
  "path": "/user/avatar", "httpMethod": "PUT", "readOnly": false,
  "requestSample": { "body": { "data": "data:image/jpeg;base64,AAAA" } },
  "responseShape": "object", "responseFields": ["ok"]
},
{
  "route": "addCustomFood", "dartMethod": "addCustomFood", "jsMethod": "addCustomFood",
  "path": "/foods/custom", "httpMethod": "POST", "readOnly": false,
  "requestSample": { "body": { "name": "测试饭团", "kcal": 250, "grams": 100, "unit": "g", "meals": ["lunch", "dinner"], "protein": 5, "carb": 40, "fat": 6, "portion": "100g", "image": "" } },
  "responseShape": "object", "responseFields": ["ok", "food"]
}
```

（`responseFields` 以 H5 云函数真实返回为准：执行时 `grep -n "'/user/profile'\|'/user/goal'\|'/user/avatar'\|'/foods/custom'" api-diet目录/index.js` 核对 PUT/POST 分支 return 形状再定稿，不符则改 fields 不改云函数。）

`contract_test.dart` invoke switch 在 `case 'getProfile':` 之后补：

```dart
      case 'updateProfile':
        return api.updateProfile(Map<String, dynamic>.from(b));
      case 'setGoal':
        return api.setGoal(b['dailyKcal'] as num, b['targetWeight'] as num);
      case 'updateAvatar':
        return api.updateAvatar(b['data'] as String);
      case 'addCustomFood':
        return api.addCustomFood(Map<String, dynamic>.from(b));
```

- [ ] **Step 2: 跑测试确认失败**

`cd ShiguangFlutter && flutter test test/data/contract_test.dart` → 编译错（方法不存在）。

- [ ] **Step 3: HealthApi 实现**

`health_api.dart` 用户段（logWeight 之后）与食物库段（getBuiltinFoods 之后）分别追加：

```dart
  /// 修改资料/身体档案（js/api.js:277 updateProfile：部分字段浅合并进用户文档，
  /// 云函数按 key 覆写——T5 发 {nickname,signature}、T6 发 body 六字段+bmi，互不越界）
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) =>
      _client.call('/user/profile', method: 'PUT', body: data);

  /// 每日目标（js/api.js:278 setGoal：body 即 {dailyKcal, targetWeight}）
  Future<Map<String, dynamic>> setGoal(num dailyKcal, num targetWeight) =>
      _client.call('/user/goal',
          method: 'PUT',
          body: <String, dynamic>{
            'dailyKcal': dailyKcal,
            'targetWeight': targetWeight,
          });

  /// 上传头像 dataURL（js/api.js:280 updateAvatar：body {data}，云端原样存字符串）
  Future<Map<String, dynamic>> updateAvatar(String dataUrl) =>
      _client.call('/user/avatar',
          method: 'PUT', body: <String, dynamic>{'data': dataUrl});
```

```dart
  /// 新增自定义食物（js/app.js:1241 调用面：{name,kcal,grams,unit,meals,protein,carb,fat,portion,image}）
  Future<Map<String, dynamic>> addCustomFood(Map<String, dynamic> food) =>
      _client.call('/foods/custom', method: 'POST', body: food);
```

- [ ] **Step 4: 双端契约测试通过**

`cd ShiguangFlutter && flutter test test/data/contract_test.dart; echo exit=$?` 全绿；仓库根 `node --test tests/contract.test.js; echo exit=$?` 全绿（H5 侧若按 jsMethod 白名单跳过未知条目则零改动——读它，若新增路由使其失败，在 H5 测试的派发处补 4 行调 `HealthAPI.updateProfile/setGoal/updateAvatar/addCustomFood`，禁改断言语义）。

- [ ] **Step 5: 全量回归 + 提交**

`dart analyze lib test`（0 问题）；`flutter test`（302+契约增量全绿）。

```bash
git add contract/fixtures/diet-core.json ShiguangFlutter/lib/data/health_api.dart \
  ShiguangFlutter/test/data/contract_test.dart tests/contract.test.js
git commit -m "feat: M5-T2 HealthApi 补 updateProfile/setGoal/updateAvatar/addCustomFood——契约 fixture 四条双端锁定"
```

（tests/contract.test.js 无改动就不加。）

---

### Task 3: dataURL 工具与选图压缩管道（image_picker 引入）

**Files:**
- Create: `ShiguangFlutter/lib/features/common/data_url.dart`
- Create: `ShiguangFlutter/lib/features/common/image_pick.dart`
- Modify: `ShiguangFlutter/pubspec.yaml`（+ `image_picker: ^1.2.3`）
- Test: `ShiguangFlutter/test/common/data_url_test.dart`、`ShiguangFlutter/test/common/image_pick_test.dart`

**Interfaces:**
- Consumes: 无（叶子工具）。
- Produces（T5/T7 消费）：
  - `const int kMaxDataUrlChars = 280000;`
  - `String dataUrlOf(List<int> bytes)` —— PNG magic 嗅定 MIME，其余按 jpeg；
  - `enum ImagePickFailure { tooLargeEncoded, readFailed }`
  - `typedef PickedImageData = ({String? dataUrl, ImagePickFailure? failure});`（dataUrl==null 且 failure==null ⇒ 用户取消，静默）
  - `Future<PickedImageData> pickCompressedImageDataUrl(ImageSource source)`（内部 `maxWidth:256, maxHeight:256, imageQuality:82`）。

- [ ] **Step 1: 失败测试**

`test/common/data_url_test.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/common/data_url.dart';

void main() {
  test('PNG magic → image/png；其余 → image/jpeg（H5 png 保透明口径）', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2]);
    expect(dataUrlOf(png), startsWith('data:image/png;base64,'));
    expect(dataUrlOf(jpg), startsWith('data:image/jpeg;base64,'));
    expect(dataUrlOf(Uint8List(0)), startsWith('data:image/jpeg;base64,')); // 短/非PNG一律jpeg
  });
  test('dataUrlOf base64 与 dart:convert 逐字一致', () {
    final b = Uint8List.fromList([1, 2, 3, 4]);
    expect(dataUrlOf(b), 'data:image/jpeg;base64,${base64Encode(b)}');
  });
  test('280000 字符闸边界', () {
    expect(kMaxDataUrlChars, 280000);
    final s = 'x' * kMaxDataUrlChars;
    expect(dataUrlTooLarge(s), isFalse);
    expect(dataUrlTooLarge('$s.'), isTrue);
  });
}
```

`test/common/image_pick_test.dart`（不触插件，只测纯映射）：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/common/image_pick.dart';
import 'package:shiguang_flutter/features/common/data_url.dart';

void main() {
  test('编码超限 → tooLargeEncoded；正常串直通（toast 文案归 UI 层）', () {
    expect(classifyPicked('a' * 100), (dataUrl: 'a' * 100, failure: null));
    expect(classifyPicked('a' * (kMaxDataUrlChars + 1)).failure,
        ImagePickFailure.tooLargeEncoded);
    expect(classifyPicked(null), (dataUrl: null, failure: null)); // 取消
  });
}
```

- [ ] **Step 2: 确认编译失败**（文件不存在）。

- [ ] **Step 3: 实现**

`lib/features/common/data_url.dart`：

```dart
// ShiguangFlutter/lib/features/common/data_url.dart
// 图片 bytes → dataURL 字符串。对齐 H5 compressAvatar 产物形态（js/app.js:1099
// png 保 png、其余 jpeg）与两道尺寸闸的「编码后」那道（:1108 dataUrl.length>280000）。
import 'dart:convert';

/// H5 头像/自定义食物图 dataURL 字符上限（js/app.js:1108 逐字数字）。
const int kMaxDataUrlChars = 280000;

bool dataUrlTooLarge(String dataUrl) => dataUrl.length > kMaxDataUrlChars;

/// PNG magic（89 50 4E 47）嗅探定 MIME，其余一律 jpeg——H5 同口径。
String dataUrlOf(List<int> bytes) {
  final isPng = bytes.length >= 4 &&
      bytes[0] == 0x89 && bytes[1] == 0x50 &&
      bytes[2] == 0x4E && bytes[3] == 0x47;
  final mime = isPng ? 'image/png' : 'image/jpeg';
  return 'data:$mime;base64,${base64Encode(bytes)}';
}
```

`lib/features/common/image_pick.dart`：

```dart
// ShiguangFlutter/lib/features/common/image_pick.dart
// 选图+压缩管道（T5 头像 / T7 自定义食物共用）。压缩不在 Dart 侧重编码：
// image_picker 在 Android 原生侧按 maxWidth/maxHeight=256 + imageQuality=82
// 降采样重编码（H5 compressAvatar 的 256 长边/q0.82 等价参数，js/app.js:1091-1097）。
// 行为差异登记：H5 的「原图 >5MB 先拒」闸（:1107）在原生重编码后不可见，
// 由「编码后 >280000 字符拒」兜底——超大原图压不进 280K 时文案同 H5「图片仍过大，请换一张」。
import 'package:image_picker/image_picker.dart';

import 'data_url.dart';

enum ImagePickFailure { tooLargeEncoded, readFailed }

typedef PickedImageData = ({String? dataUrl, ImagePickFailure? failure});

/// 纯映射（可单测）：null=取消静默；超限→tooLargeEncoded。
PickedImageData classifyPicked(String? dataUrl) {
  if (dataUrl == null) return (dataUrl: null, failure: null);
  if (dataUrlTooLarge(dataUrl)) {
    return (dataUrl: null, failure: ImagePickFailure.tooLargeEncoded);
  }
  return (dataUrl: dataUrl, failure: null);
}

/// 拉起系统选择器（camera/gallery 由调用方传），返回压缩后 dataURL。
Future<PickedImageData> pickCompressedImageDataUrl(ImageSource source) async {
  final XFile? file;
  try {
    file = await ImagePicker().pickImage(
        source: source, maxWidth: 256, maxHeight: 256, imageQuality: 82);
  } catch (_) {
    return (dataUrl: null, failure: ImagePickFailure.readFailed);
  }
  if (file == null) return (dataUrl: null, failure: null); // 取消
  try {
    return classifyPicked(dataUrlOf(await file.readAsBytes()));
  } catch (_) {
    return (dataUrl: null, failure: ImagePickFailure.readFailed);
  }
}
```

pubspec `dependencies:` 追加 `image_picker: ^1.2.3`，`flutter pub get`。

- [ ] **Step 4: 插件即装即验构建（M4 permission_handler 教训）**

`flutter build apk --debug > ../.mimosa/m5t3-build.log 2>&1; echo exit=$?` ——exit=0 且产物 mtime 新。任何 AGP/manifest merge 报错当场处理（预期零处理：image_picker 无权限声明要求，Android 侧走系统相机/相册 intent）。

- [ ] **Step 5: 测试 + 提交**

`flutter test test/common/; dart analyze lib test` 绿。

```bash
git add ShiguangFlutter/pubspec.yaml ShiguangFlutter/pubspec.lock ShiguangFlutter/lib/features/common \
  ShiguangFlutter/test/common
git commit -m "feat: M5-T3 dataURL 工具+选图压缩管道（image_picker 256/q82 等价 H5 compressAvatar，原生 5MB 闸由编码闸兜底=登记差异）"
```

---

### Task 4: FoodThumb 组件与三列表接线

**Files:**
- Create: `ShiguangFlutter/lib/features/common/food_thumb.dart`
- Modify: `ShiguangFlutter/lib/features/record/search_sheet.dart`（结果行 emoji 位 :265 附近）
- Modify: `ShiguangFlutter/lib/features/record/record_screen.dart`（当日记录行 emoji 位——H5 app.js:546 同构处）
- Test: `ShiguangFlutter/test/common/food_thumb_test.dart`

**Interfaces:**
- Consumes: `dataUrlOf`/`kMaxDataUrlChars`（T3，仅解码路径约定，不直接调）。
- Produces: `FoodThumb({required String? source, String emoji = '🍽️', double size = 40})`（source 空/坏→emoji 文本回退；`data:` → Image.memory；`http(s)` → Image.network + errorBuilder 回退）。

- [ ] **Step 1: 失败测试**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/common/food_thumb.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

/// 1x1 合法 PNG（恒字节，非临时生成）
final _png1x1 = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

void main() {
  testWidgets('空 source → emoji 文本', (tester) async {
    await tester.pumpWidget(_wrap(const FoodThumb(source: '')));
    expect(find.text('🍽️'), findsOneWidget);
    await tester.pumpWidget(_wrap(const FoodThumb(source: null, emoji: '🍎')));
    expect(find.text('🍎'), findsOneWidget);
  });
  testWidgets('dataURL → Image.memory 渲染成功', (tester) async {
    final url = 'data:image/png;base64,${base64Encode(Uint8List.fromList(_png1x1))}';
    await tester.pumpWidget(_wrap(FoodThumb(source: url)));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('🍽️'), findsNothing);
  });
  testWidgets('坏 dataURL（非法 base64/非法图像）→ emoji 回退', (tester) async {
    await tester.pumpWidget(_wrap(const FoodThumb(source: 'data:image/png;base64!!!')));
    expect(find.text('🍽️'), findsOneWidget);
    await tester.pumpWidget(
        _wrap(const FoodThumb(source: 'data:image/png;base64,@@@')));
    expect(find.text('🍽️'), findsOneWidget);
  });
  testWidgets('非 data/http 前缀（脏值）→ emoji 回退，不抛', (tester) async {
    await tester.pumpWidget(_wrap(const FoodThumb(source: 'img/meals/x.jpg')));
    expect(find.text('🍽️'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 实现**

`lib/features/common/food_thumb.dart`：

```dart
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
```

- [ ] **Step 3: 两处接线**

search_sheet.dart 结果行：把 emoji `Text(...)` 位替换为 `FoodThumb(source: (f['image'] as String?) ?? '', emoji: (f['emoji'] as String?) ?? '🍽️')`；record_screen 当日记录行同理（消费记录 map 的 `image`/`emoji` 键，record_controller 落 body 时已带，:666/:754 抄 H5 同构）。两处尺寸先 40，目检后按观感调（R4）。

- [ ] **Step 4: 回归 + 模拟器目检（R4）**

`flutter test`（全量）+ `dart analyze lib test` 0。装 debug 包进模拟器：搜索「鸡蛋」看内置条目（无图→emoji 正常）、uitest01 云端已存带图自定义食物（M5-H5 侧先手建一条含小图）Flutter 应显缩略图——若 fixture 图难造，退化为单测覆盖+真机 T8 抽查，报告登记。截图留档 `.mimosa/`。

- [ ] **Step 5: Commit**

```bash
git add ShiguangFlutter/lib/features/common/food_thumb.dart ShiguangFlutter/lib/features/record \
  ShiguangFlutter/test/common/food_thumb_test.dart
git commit -m "feat: M5-T4 FoodThumb 缩略图组件（dataURL/URL/坏值三态回退 emoji）+搜索与记录行接线"
```

---

### Task 5: 资料卡——头像/昵称/签名头部与编辑弹层

**Files:**
- Create: `ShiguangFlutter/lib/features/profile/profile_providers.dart`
- Create: `ShiguangFlutter/lib/features/profile/profile_edit_sheet.dart`
- Modify: `ShiguangFlutter/lib/features/profile/profile_screen.dart`（标题下插 `_profileHead()`；T6 还要在本文件接线身体卡，预留顺序：资料头→体重卡→身体卡(T6)→提醒卡→退出）
- Test: `ShiguangFlutter/test/profile_head_test.dart`

**Interfaces:**
- Consumes: `HealthApi.getProfile/updateProfile/updateAvatar`（T2）、`pickCompressedImageDataUrl`（T3）。
- Produces: `final profileProvider = FutureProvider<Map<String, dynamic>>((ref) => ref.watch(healthApiProvider).getProfile());`（T6 消费同一 provider 与 T2 方法）；`Future<void> openProfileEditSheet(BuildContext, WidgetRef)`。

- [ ] **Step 1: 失败测试**（要点断言，样板抄 profile_screen_test 的 profileContainer+NoopReminderScheduler）

```dart
// 4 个用例：
// ①头部渲染：getProfile 桩 {nickname:'小满', signature:'把每一餐，记成时光', avatarText:'满', avatarData:null, goal:{...}, body:{...}, id:'u_test'}
//   → find.text('小满')、find.text('把每一餐，记成时光')、find.text('满')（无头像画首字）。
// ②昵称闸：开弹层清空→保存 → SnackBar「昵称不能为空」，updateProfile 计数 0。
// ③保存链：改昵称→保存 → envelopes 断 PUT /user/profile body 含 {nickname,signature}
//   → 成功后 profileProvider 重取（GET /user/profile 计数 +1）+ toast「资料已保存」+ 弹层关闭。
// ④头像失败注桩：routes{'/user/avatar':(status:500,text:'{"message":"boom"}')}
//   → toast「保存失败：boom」路径经 updateAvatar 触发（头像链在 UI 可注入桩，插件选择器
//   不在 widget test 触达——pickCompressedImageDataUrl 以顶层函数引用注入，测试传 fake）。
```

实现提示：④把「选图→上传」封成 `Future<void> _pickAvatar(WidgetRef ref)`，内部才调 pickCompressedImageDataUrl；测试直接调上传失败分支可用 `profileProvider` 失效断言替代插件链（选图链留真机 T8 抽查），登记覆盖边界。

- [ ] **Step 2: profile_providers.dart**

```dart
// ShiguangFlutter/lib/features/profile/profile_providers.dart
// 用户资料唯一读取源（GET /user/profile 一次拿全：nickname/signature/avatar/
// goal/body/bodyUpdatedAt，fixture 契约已锁 responseFields）。T6 身体卡共用。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/home_controller.dart' show healthApiProvider;

final profileProvider = FutureProvider<Map<String, dynamic>>((ref) =>
    ref.watch(healthApiProvider).getProfile());
```

- [ ] **Step 3: 头部组件**（profile_screen.dart 内新增，样式 R4 自由，行为逐字）

渲染规则（H5 renderProfile :1004-1020）：`avatarData` 非空→画头像图（圆形，FoodThumb size:56 复用）；否则画 `avatarText || nickname 首字`。点头部→`openProfileEditSheet`。加载态画占位「…」，失败画「未登录信息」占位可点重试（`ref.invalidate(profileProvider)`）。

- [ ] **Step 4: 编辑弹层**（profile_edit_sheet.dart， showModalBottomSheet + Consumer）

字段：头像预览行（圆形 FoodThumb/首字 + 「更换头像」按钮）、「昵称」TextField、「个性签名」TextField。行为逐字 H5 :1153-1166：昵称 trim 空→toast「昵称不能为空」return；「更换头像」→`pickCompressedImageDataUrl(ImageSource.gallery)`：取消静默；tooLargeEncoded→「图片仍过大，请换一张」；readFailed→「图片处理失败」；成功→`updateAvatar(url)`→toast「头像已更新」→`ref.invalidate(profileProvider)`（H5 :1114-1115 同款重取）。保存→`updateProfile({'nickname':n,'signature':s})`→invalidate→toast「资料已保存」；ApiException→toast「保存失败：${e.message}」，其它→「保存失败：网络异常」。

- [ ] **Step 5: 回归 + 目检 + 提交**

`flutter test`、`dart analyze lib test`；模拟器目检头部/弹层（键盘遮挡按 Back 再截）。

```bash
git add ShiguangFlutter/lib/features/profile ShiguangFlutter/test/profile_head_test.dart
git commit -m "feat: M5-T5 我的页资料卡——头像(选图压缩上传)/昵称/签名编辑弹层，链路与文案逐字对齐 H5"
```

---

### Task 6: 身体参数卡——展示、代谢明细、编辑弹层与目标联动

**Files:**
- Create: `ShiguangFlutter/lib/features/profile/body_profile_card.dart`
- Modify: `ShiguangFlutter/lib/features/profile/profile_screen.dart`（体重卡后插 `BodyProfileCard()`）
- Test: `ShiguangFlutter/test/body_profile_card_test.dart`

**Interfaces:**
- Consumes: `profileProvider`（T5）、`Body.fromMap`/`computeMetabolism`/`activity`（domain 现成）、`updateProfile/setGoal`（T2）、`jsFixed1`（js_compat）。
- Produces: `BodyProfileCard()`（ConsumerWidget）；`Future<void> saveBodyProfile(WidgetRef ref, Map<String, Object?> bodyMap)` 供弹层与测试直调。

- [ ] **Step 1: 失败测试**（profileContainer 注桩）

断言五链：
①卡面六值：profile 桩 body{168,66.66,30,female,moderate,500} → 文本含 `168`、`66.66 kg`、`30 岁`、`女`、`中度`、BMI `23.6`；
②代谢区：`computeMetabolism(Body.fromMap(同值), goal.targetWeight ?? 55, null)` 纯 Dart 期望值直比（BMR/TDEE/建议摄入三数）；**降级登记**：H5 传 actualDeficit（localStorage 近7天均值），Flutter 本任务传 null=预设缺口口径，卡上缺口行标注「预设缺口」（报告登记差异，M6 若做实际缺口再补）；
③保存链：弹层改 heightCm=170→保存 → 第一发 envelope `PUT /user/profile` body 六字段+bmi（bmi==`jsFixed1(66.66/(170/100)^2)`）；第二发 `PUT /user/goal` body `{dailyKcal: suggest, targetWeight: tw}`，suggest=重算值；profileProvider 重取计数 +1；toast「身体档案已保存」；
④无变化不重发 goal：保存但 suggest==profile.goal.dailyKcal → 仅 1 发 PUT /user/profile；
⑤失败链：`/user/profile` status:500 message「x」→ toast「已本地保存：x」（逐字 H5 :1698），且**不**发 setGoal、invalidate 仍发生（重取回真值）。

- [ ] **Step 2: 实现**

`BodyProfileCard`：watch profileProvider；数据 `final b = Body.fromMap(((p['body'] ?? const {}) as Map).cast<String, Object?>())` 叠加 `weightKg` 以 bodyMetrics 为准？——**不叠加**：H5 effectiveBody 用 profile.body + 本地缓存，体重卡独立；Flutter 单一事实源=profile.body，体重卡 logWeight 成功后现有 `ref.invalidate(profileWeightProvider)` 之外**追加 `ref.invalidate(profileProvider)`**（profile_screen.dart 一行，保证两卡体重同步）。
六值行+代谢区（BMR/TDEE/建议摄入/缺口 四行小字公式注记 R4 自由排布，etaText/rangeText 原文展示——domain 已备好逐字文案）。
编辑弹层：身高 stepper ±1（100-250）、体重 ±0.5（30-200，toSigned 1 位小数 `toFixed(1)` 口径 H5 :1668）、年龄 ±1（10-100）、性别分段（女|男）、活动 chips 五档（label 用 `activity[x]!.label`）、缺口分段（温和 300/标准 500/积极 750）；边界 toast「已到上限/已到下限」复用体重卡 `_bump` 模式（抽公共 `String bumpToast(...)` 或就地同逻辑——就地，别过度抽象）。
`saveBodyProfile`：

```dart
Future<void> saveBodyProfile(WidgetRef ref, Map<String, Object?> bodyMap) async {
  final api = ref.read(healthApiProvider);
  final profile = ref.read(profileProvider).value ?? const <String, dynamic>{};
  final goal = (profile['goal'] as Map?)?.cast<String, dynamic>() ?? const {};
  final tw = (goal['targetWeight'] as num?)?.toDouble();
  final body = Body.fromMap(bodyMap);
  try {
    await api.updateProfile(bodyMap);
    final m = computeMetabolism(body, tw, null);
    if (m.suggest != (goal['dailyKcal'] as num?)) {
      await api.setGoal(m.suggest, tw ?? body.weightKg.toDouble());
    }
    ref.toast('身体档案已保存');
  } catch (e) {
    ref.toast('已本地保存：${e is ApiException ? e.message : '网络异常'}');
  } finally {
    ref.invalidate(profileProvider);
    ref.invalidate(summaryProvider); // 首页环目标联动（M2 现成 family）
  }
}
```

（`toast` 落地方式：函数签名收 `void Function(String) toast` 参数由调用方传 `_toast`——避免 ref 扩展魔法；bmi 在弹层收集时算好：`'bmi': jsFixed1(w / pow(h / 100, 2))`。）

- [ ] **Step 3: 回归 + 目检 + 提交**

全量 test/analyze；模拟器目检（弹层含六组控件，滚动可用性 R4 关注）；`git add ShiguangFlutter/lib/features/profile ShiguangFlutter/lib/features/profile/profile_screen.dart ShiguangFlutter/test/body_profile_card_test.dart` → `git commit -m "feat: M5-T6 身体参数卡——六值+代谢明细+编辑弹层，保存链复刻 H5 updateProfile→setGoal 联动首页目标（实际缺口口径降级登记）"`。

---

### Task 7: 自定义食物表单（选图+入库+记一餐）

**Files:**
- Create: `ShiguangFlutter/lib/features/record/custom_food_sheet.dart`
- Modify: `ShiguangFlutter/lib/features/record/search_sheet.dart`（空结果区加「＋ 自定义食物」按钮 → 开表单；成功回填重查结果，H5 fillSheetResults :1256 等价）
- Test: `ShiguangFlutter/test/custom_food_sheet_test.dart`

**Interfaces:**
- Consumes: `addCustomFood/addFoodRecord`（现成+T2）、`pickCompressedImageDataUrl`（T3）、`FoodThumb`（T4，预览用）、MEAL_NAMES（domain constants 现成，执行时核名）。
- Produces: `Future<void> openCustomFoodSheet(BuildContext context, {required String meal, String? initialName, required void Function() onSaved})`——onSaved 由 search_sheet 传「以当前关键词重查」。

- [ ] **Step 1: 失败测试**（RecordingAdapter）

断言链（表单开在 profileShell 之外的 record 页 context——测试挂最小壳）：
①默认值：initialName='测试饭团' → 名称预填；餐次默认=传入 meal（lunch/dinner 均归「正餐」档，CF_MEAL_MAP :1176）；单位默认 g；
②宏量自动热量：填 p=5,c=40,f=6 且未手改 kcal → 热量框显示 `250`（`5*4+40*4+6*9`，:1190-1197 Math.round 同值）；手改 kcal=300 后再改宏量 → 保持 300（cfKcalManual 闸）；
③名称闸：清空名称保存 → toast「请填写食物名称」，无请求；
④热量闸：kcal=0 且三素空 → toast「请填热量，或先填三大营养素自动算」；
⑤入库链：name=测试饭团/grams=100/kcal=250/meals=正餐 → `POST /foods/custom` body 逐键 `{name,kcal,grams,unit:'g',meals:['lunch','dinner'],protein:5,carb:40,fat:6,portion:'100g',image:''}`；onSaved 被调；toast「已存入食物库，搜索可用」；
⑥记一餐链（meal=breakfast 入口）：入库后第二发 `POST /diet/records` body 含 `{date: todayIso(), meal:'breakfast', name, portion:'100g', kcal:250, emoji:'🍽️', image:'', protein,carb,fat}` + toast「已记入早餐 · 测试饭团」（:1244-1247 逐字）；
⑦失败：500 message「m」→ toast「保存失败：m」。

- [ ] **Step 2: 实现**

表单控件：名称 TextField（initialName 预填 :1199 语义=搜索词）；克数数字框 + 单位分段（克|毫升）；热量数字框（onChangeManual 置 `_kcalManual`）；三素三框（onChange→`_autoKcal()`）；餐次三分段（早餐|正餐|零食，默认由入参 meal 映射：breakfast→早餐，snack→零食，其余→正餐）；图片行：「拍照」（camera）与「从相册选择」（gallery）两钮 + FoodThumb 预览 + 清除按钮；预览下方空态画 🍽️（renderCfPreview :1203-1206）。图片失败/超限 toast 同 T5 文案。两保存按钮：「保存并记入{早餐|中餐|晚餐|夜餐按 MEAL_NAMES[入参 meal]}」（主按钮，标题随入参餐次——`fromLib` 分支 Flutter 无管理页不实现）与「仅存入食物库」。提交体组装逐字 :1241（`portion: grams != 0 ? '$grams$unit' : '1 份'`）。saveCustomFood 成功序：addCustomFood→（记入则 addFoodRecord）→pop→onSaved→toast；refresh：`ref.invalidate(recordsProvider(date))`+`ref.invalidate(summaryProvider(date))`（对齐 H5 :1246-1247 refreshToday+loadRecordPage）。

- [ ] **Step 3: 接线 search_sheet**

空结果区（现 :222 文案下）加 OutlinedButton.icon「＋ 自定义食物」→ `openCustomFoodSheet(context, meal: 当前餐次, initialName: 关键词, onSaved: () => _search(_keywordCtrl.text))`。

- [ ] **Step 4: 回归 + 目检 + 提交**

全量 test/analyze；模拟器目检（表单滚到底两按钮不遮、软键盘态截一张）；提交：`git commit -m "feat: M5-T7 自定义食物表单——宏量自动热量/双保存模式/选图压缩上传，搜索空结果入口接线（文案闸逐字 H5）"`。

---

### Task 8: 收官——版本、全量门禁、release 双端装机与互通抽查

**Files:**
- Modify: `ShiguangFlutter/pubspec.yaml`（`version: 2.3.0+20300`）
- Create: 仓库根 `食光Flutter-v2.3.0.apk`（arm64 release 正式包，随 release 入库）
- Create: `.superpowers/sdd/2026-09-25-flutter-m5-release-profile-visuals/task-8-report.md`（git-ignore）

- [ ] **Step 1: 版本升档 + 四道门禁**

pubspec → `2.3.0+20300`。依次跑并记原始输出：`dart analyze lib test`（0）；`flutter test`（全量报数）；仓库根 `node --test "tests/**/*.test.js"`（69/69 零 diff——M5 不得触碰 H5 js）；`npm run check:version`（1.4.0 + Flutter 公式 2*10000+3*100+0 双验）。

- [ ] **Step 2: release 构建与正式包入库**

```bash
cd ShiguangFlutter && flutter build apk --release --split-per-abi > ../.mimosa/m5t8-build.log 2>&1; echo exit=$?
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ../食光Flutter-v2.3.0.apk
ls -la ../食光Flutter-v2.3.0.apk
```

（命名先例：H5 用 `食光-v1.4.0.apk`；Flutter 线带线名防混淆。体积预期 20-30MB。）`git add 食光Flutter-v2.3.0.apk` 与 pubspec 同提交。

- [ ] **Step 3: 模拟器全链目检（R4 收口）**

x86_64 release 包装 emulator：登录 uitest01 → 我的页五区（资料头/体重/身体/提醒/退出）逐屏截图 → 搜「鸡蛋」缩略图 → 自定义食物建「验收奶茶」（相册选图若模拟器图库空：`adb push .mimosa/shot-v140-ex.png /sdcard/Pictures/` 后选它）→ 首页环目标随身体参数改 170cm 后刷新。检查截图无黑屏（~71KB 全黑特征=息屏，重截）。

- [ ] **Step 4: 真机 release 装机单（老大执行）**

报告含步骤：①`adb uninstall com.healthydiet.shiguang_flutter`（debug/release 签名不同必须卸载，云端数据无损）②`adb install -r ShiguangFlutter/build/.../app-arm64-v8a-release.apk` ③重登录 → 图标/名称目检 ④互通抽查：Flutter 建带图自定义食物 → H5 搜索见同图；H5「我的」改昵称 → Flutter 重进页反映；⑤拍照链真机验（模拟器无相机）。

- [ ] **Step 5: task-8-report.md + 提交**

报告含：R4 目检差异清单、各任务登记面（5MB 闸降级/预设缺口/预 26 图标/坏图回退 emoji/fromLib 不做）、门禁原始输出、真机单。全量再跑一遍四门禁确认零回归后：

```bash
git add ShiguangFlutter/pubspec.yaml ShiguangFlutter/pubspec.lock 食光Flutter-v2.3.0.apk
git commit -m "build: M5 收官——2.3.0+20300 四门禁绿，食光Flutter-v2.3.0 正式包入库（arm64 release 签名）"
```

合入 main/推送**不在本计划内**——等老大单字令。

---

## Self-Review 结论

1. **Spec 覆盖**：A→T1/T2 无关部分+T8（keystore/名称/图标/split-per-abi/入库/换签重装 runbook 全落）；B→T5（资料卡）/T6（身体参数+目标联动）；C→T4；D→T3+T7；门禁/R4→每任务目检步+T8；风险四条→T1（预 26 降级面）/T8 Step4（换签卸载）/T1 Step1（密码备份即告即存）/T3 Step4（插件即装即验）。无遗漏。
2. **占位扫描**：无 TBD/「适当处理」；所有文案给了 H5 行号锚或逐字值。
3. **类型一致**：`pickCompressedImageDataUrl/PickedImageData/ImagePickFailure`、`FoodThumb(source/emoji/size)`、`profileProvider`、`saveBodyProfile(ref→toast 参数化)`、`openCustomFoodSheet(meal/initialName/onSaved)` 在 T5-T8 的引用与本定义逐字一致；`updateProfile/setGoal/updateAvatar/addCustomFood` 签名 T2 定义、T6/T7 消费一致。
