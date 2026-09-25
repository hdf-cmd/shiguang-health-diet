# M5 签名发布线 + 个人信息 + 食物图片 设计文档

日期：2026-09-25 ｜ 里程碑：M5（Flutter 重写第 5 站）｜ 前置：M1-M4 已合入推送（origin/main=`5479baa`，2.2.0+20200）

## 背景与裁定记录

食光 Flutter 重写按「一个里程碑一份计划」推进。M5 原住在总 spec 中为「签名 release 发布线」；本轮老大加令：**后续每轮 UI 改动须开模拟器目检布局与组件适配，允许 Flutter 侧自主创新**（记为 R4；数据行为仍按 bug-for-bug 对齐 H5，创新只花在视觉与交互层）。经问答定稿：

- 范围四选全收：A 签名发布线、B 我的页·个人信息（**全部**：资料卡+身体参数）、C 食物图片缩略图、D 自定义食物拍照上传；
- 签名库：**新建独立 keystore**（与 H5 签名材料脱钩），随机强密码，密码备份责任在老大（当场抄录/存网盘）；
- 提醒到点长时观察：老大明示「先不用管」，M4 验收按已 PASS 收官。

## 目标与验收判据

1. release 签名包（`--split-per-abi`）安装老大手机跑日常，应用名「食光」、食光启动图标；
2. Flutter「我的」与 H5 信息面全对齐：头像/昵称/签名 + 身高/年龄/性别/活动量/目标缺口，保存后首页热量目标真实联动；
3. 带图自定义食物与头像 H5↔Flutter 双向互通抽查（uitest01 双端）；
4. 四道门禁全绿：`dart analyze lib test`、`flutter test`、H5 `node --test` 零 diff、`npm run check:version`；
5. 每任务收官过模拟器目检（R4），目检发现的不适配件允许当场调整并在报告登记差异。

版本升 **2.3.0+20300**（H5 线不动，仍 1.4.0）。正式 release 包照惯例随 release 入库。

## 现状事实（本设计的依据，均已核）

- 食物 `image` 字段云端已有且 Flutter 数据层已透传（search_sheet.dart:123），UI 未渲染；H5 渲染位=搜索结果行（app.js:546）、常吃行（:637），行为=「有图画图、无图回退 emoji」；image 值两种形态：dataURL（自定义食物/头像）与 URL。
- Flutter「＋自定义食物」表单 M2 未做（search_sheet.dart:11-12 登记"属后续任务"）⇒ D 是整表单落地，非仅加图。
- 身体参数保存链路（H5 app.js:1680-1718）：表单收集→本地生效→`PUT /user/profile`（updateProfile）→`syncTarget`：`computeMetabolism(body, targetWeight).suggest` 与当前目标不等时 `PUT /user/goal` {dailyKcal, targetWeight}。云端 api-diet 一行不改（路由 js/api.js:62-69 全部现成：profile GET/PUT、setGoal、avatar PUT dataURL、bodyMetrics GET）。
- 头像压缩管道（H5 app.js:1085-1101）：canvas resize 长边≤256、jpeg q0.82（png 保留透明）、字符串 >280KB 拒收；自定义食物图同管道。H5 选图走 `<input type=file>`（相册/相机系统选择器）。
- Flutter domain 已全量移植身体参数（BodyProfile/metabolism.dart/constants.dart，缺省=H5 BODY_DEFAULT 语义）；「我的」页现仅体重卡+提醒区+登出。
- 图标：H5 为矢量自适应（drawable/ic_launcher_foreground.xml + mipmap-anydpi-v26），Flutter 现为模板默认 Flutter 图标；minSdk=24 ⇒ API 24/25 需 PNG 兜底（矢量按密度导出，风险项）。
- keystore 基线：HealthyDiet/keystore/ 从不入库（.gitignore），ShiguangFlutter 侧同规则新建（android/key.properties + *.jks/*.keystore 忽略）。

## 范围拆解

### A. 签名发布线

1. keytool 生成 `shiguang-flutter-release.jks`（RSA 2048、有效期 10000 天、随机 24 位密码），落 `ShiguangFlutter/android/`；`key.properties` 同款 git-ignore；密码当场展示并提醒老大备份，仓库零痕迹。
2. `build.gradle.kts`：release signingConfig 读 key.properties（缺失时回退 debug 签名并警告——CI/他人 clone 不断构建）；
3. 应用名：manifest `android:label` →「食光」；启动图标：移植 H5 自适应图标 XML + 矢量渲染各密度 PNG 兜底（24/25 覆盖）；
4. `flutter build apk --release --split-per-abi` → arm64-v8a 包入库（命名对齐 H5 惯例：`食光Flutter-v2.3.0.apk`）+ 真机覆盖安装验证（debug 包与 release 签名不同，须先卸重装——数据在云端无损失，runbook 写明）。

### B. 我的页·个人信息

1. **资料卡**（页面头部）：头像（有 avatarData 画圆图，无则昵称首字/默认emoji，与 H5 renderProfile 对齐）+ 昵称 + 个性签名；点击进编辑弹层：昵称/签名为文本框（长度闸照 H5），头像走 D 的压缩管道 `PUT /user/avatar`；
2. **身体参数卡**：展示 身高/年龄/性别/活动量/目标缺口 + 派生 BMR/TDEE/建议目标（代谢明细照 H5 renderMetab 的信息量，版式 Flutter 化——R4 授权区）；编辑弹层：数值滑杆/输入 + 性别/活动量/缺口分段选择（选项集=constants.dart activity）；
3. 保存链路 bug-for-bug：本地 state 生效 → `updateProfile(body)` → 目标 suggest 变化则 `setGoal`；失败 toast「已本地保存：…」（逐字 H5）；成功后失效 summaryProvider 使首页环目标联动；
4. HealthAPI 补方法：getProfile/updateProfile/setGoal/updateAvatar（契约 fixture 加路由，双端 contract_test 锁形）。

### C. 食物图片缩略图

1. 新组件 `FoodThumb`（size 对齐 H5 `.thumb`）：`data:` 前缀 → base64 解码 `Image.memory`；`http(s)` → `Image.network`（loading/error 均回退 emoji——等效 H5 onerror）；空串/null → emoji；
2. 接入位：搜索结果行、常吃列表行、记录页当日记录行（凡 H5 画 thumb 处）；自定义表单与弹层预览复用同组件。

### D. 自定义食物（表单+拍照上传）

1. 搜索弹层空结果处 + 搜索框旁「＋ 自定义食物」入口（H5 同位）→ 底部表单：名称/热量 kcal/每份克数/单位(g·ml·个…)/餐次多选/蛋白质·碳水·脂肪(选填)/份量描述，字段与校验照 H5 cf 表单（app.js:1171-1267）；提交 `addCustomFood` 同路由；
2. 图片位：拍照/相册二选一（image_picker 新依赖），压缩=decode→长边≤256 resize→jpeg q0.82→dataURL，>280KB 拒「图片仍过大，请换一张」（逐字 H5）；预览可删除；
3. 权限：相机授权首弹（manifest 补 CAMERA，permission 走系统默认弹窗）；选图不占存储权限（image_picker 无需 READ_MEDIA）。

## 测试面

- 每任务 TDD 红绿；FoodThumb 三态（dataURL/URL/空+错误回退）、压缩闸（>280KB 拒、png 透明保留路径）、body-save 链路（RecordingAdapter 断 updateProfile+setGoal 双发、失败路径 toast 逐字）、资料卡编辑、自定义表单提交体逐字段快照；
- 契约 fixture 增 profile/goal/avatar/addCustomFood-with-image 路由，H5 侧零 diff；
- 互通抽查：Flutter 建带图自定义食物 → H5 搜索可见同图；H5 改昵称/身体参数 → Flutter 反映；
- 模拟器目检（R4）+ 真机 release 装机。

## 风险登记

1. API 24/25 图标 PNG 兜底需矢量栅格化（无现成工具则用 Flutter 侧 ImageGen/矢量转写简单近似——目标「像食光」而非像素级一致）；
2. debug→release 换签名须卸载重装（runbook 预告，云端数据无感）；
3. keystore 丢失=该线无法覆盖升级；密码仅存老大处与本机 git-ignore 文件两处；
4. image_picker 与 AGP 兼容面（M4 permission_handler 版本钉扎的教训：装后立即 assembleDebug 验证再进测试）。

## 非目标（明确不做）

运动打卡 UI、餐盘日期切换 ‹ ›、喝水进度卡/灵动岛（M4 降级面维持）、失焦归一化（仍待产品裁定）、foodFreq 跨账号 prefs（M6 池）、H5 侧任何回填、云函数任何改动。
