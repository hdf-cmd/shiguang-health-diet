# 食光工程规范（项目全局）

本文件是本项目长期生效的编码与交付标准。所有新增/修改代码按此执行；与个人偏好冲突时，以本文件为准。

## 一、十四项质量基线

### 1. 可维护性
- 新增云函数路由必须放在 `cloudfunctions/api-diet/services/`，`index.js` 只做参数解析与 dispatch。
- 单个 Dart 文件超过 ~350 行、云函数文件超过 ~500 行时，先拆再继续加功能。
- 纯逻辑（校验、映射、排序、份量换算）必须与 UI/网络/数据库分离，放在可单测的文件里。

### 2. 可测试性
- 新增纯逻辑：必须加 `node --test` / `flutter test` 用例，覆盖正常、边界、失败三类。
- 新增云端路由：service 接受依赖注入（db/fetch/clock），用 fake 依赖写集成测试。
- 新增 Flutter 弹层/页面：至少给可提取的表单换算、候选选择逻辑写单测；关键入口补 widget 测试。

### 3. 可靠性 / 健壮性
- 外部请求必须有超时、有限重试、明确的失败分类；区分「未命中」与「服务不可用」。
- 所有异步 UI 写入在 `await` 后检查 `mounted`；用户关闭弹层后不得继续后台批量写入。
- 空结果、缺字段、模型返回非法结构都必须显式处理，禁止静默丢数据。
- 用户选中但无效的行（未命中、份量为 0）必须拦下并提示，不能跳过。

### 4. 安全性
- 所有用户数据查询必须带 `uid` 约束。
- 全局缓存集合（如 `off_products`）权限设为 ADMINONLY，只允许云函数访问。
- 模型日志不得记录用户原文/模型原文；只记录长度、分类、requestId。
- 密钥只放云端环境变量或客户端安全存储；禁止进入仓库、日志、APK 明文资源。
- AI 只允许输出白名单字段；营养数值必须来自库内数据或明确标记为「AI 估算」。

### 5. 性能效率
- 禁止 N+1：循环内不得重复读同一 profile/config；先读一次再传入。
- 查询必须有上限（内置库/自定义库/候选数），缓存要设 TTL。
- 不提前优化；但已知 O(n²)、无界集合、无限缓存必须当次修掉。

### 6. 可观测性
- 云函数日志使用固定前缀：`OFF_ERR`、`OFF_CACHE_*`、`MEAL_PARSE_FAIL`、`MEAL_INVALID`、`MEAL_MATCH_ERR`。
- 日志包含 requestId/分类/长度/耗时，不包含 PII、token、完整用户文本。
- 客户端失败必须有用户可读文案；开发期可 `debugPrint`，禁止把异常静默吞掉。

### 7. 可复用性
- 云端返回行保持与 `/foods/search` 同形，客户端复用份量层/缩略图/记录链路。
- 公共能力提取为纯函数或 service；禁止为了复用强行耦合两个业务域。
- 客户端/云端需要同一算法（如条码校验位）时，两侧各自实现并各自测试，不共享运行时依赖。

### 8. 一致性
- 路由命名：资源复数 + 动作，如 `/foods/barcode`、`/ai/meal-parse`。
- 响应 envelope 统一 `{ ok, ... }`；失败统一 `{ ok:false, message }`。
- Flutter key 命名沿用 `sheet-xxx-open`、`xxx-close`；文案用简体中文，代码标识用英文。
- 新代码风格与相邻文件一致，不引入第二套状态管理/网络库/主题 token。

### 9. 可协作性
- 提交前必须通过本文件「交付门禁」。
- 注释只写「为什么/约束/踩坑」，不写「这行做了什么」。
- 接口变更必须同步更新调用方、测试、契约文档。
- 不提交临时脚本、截图、构建沙盒、密钥文件。

### 10. 可部署性 / 可运维性
- 云函数部署前先下载旧包备份到 `cloud-backup/rollback-<日期>/`。
- 部署后核验 Runtime、Timeout、Memory、Handler、Status、ModTime。
- 发布包必须 bump 版本号，记录 SHA256/MD5/大小/签名证书 SHA256。
- 配置外置：环境变量、`key.properties`、`tcb_custom_login.json` 不入库。
- 任何上线变更必须有回滚路径。

### 11. 可移植性 / 兼容性
- 云函数运行时版本显式锁定（当前 `Nodejs18.15`），不依赖 CLI 智能推断。
- Android minSdk/targetSdk 改动必须记录；iOS 未配置的能力不得在 Android 文案中承诺。
- Windows 中文路径下 release 构建走 ASCII 沙盒，必须复制 `pubspec.lock`。

### 12. 资源管理
- Flutter：`TextEditingController`、`ScrollController`、相机/蓝牙控制器、Timer 必须 dispose。
- 云函数：`AbortController` 的 timer 必须 `clearTimeout`；数据库连接由 SDK 管理，不手工持有。
- 批量操作必须可中断；用户离开页面后停止后续写入。

### 13. 简洁性
- KISS/YAGNI：不为假想需求造抽象；三行重复优于过早抽象。
- 新功能优先复用现有链路；引入新依赖前先查本地知识库/现有依赖。
- 单函数只做一件事；路由只做解析与委托。

### 14. 可演进性
- 响应新增字段必须向后兼容（新增可选字段，不改变既有字段语义）。
- 候选/来源等可扩展信息用数组或 `source` 字段承载，不写死单一实现。
- 数据结构变更要评估旧缓存/旧客户端兼容性；必要时加 `version` 字段。

## 二、项目固定约束

- 客户端：Flutter 2.x 线在 `ShiguangFlutter/`；H5 旧线在根目录，非必要不同步改。
- 后端：CloudBase 单入口 `api-diet`，Node18.15 / 60s / 256MB。
- 数据：`custom_foods` 按 uid 隔离；`off_products` 全局缓存、ADMINONLY、30 天 TTL。
- AI：模型只抽食物名/份量，营养来自内置库/自定义库；无命中才走 `/ai/food-estimate` 并标「AI 估算」。
- AI 单位：模型回传的 `unit` 必须由原文「数字+单位」佐证；「一瓶200g」取 200g，不取包装数量 1；原文无单位则丢弃模型补的单位。
- 条码未收录：优先拍包装营养成分表，云端 `/ai/nutrition-label` 读每 100g/ml；用户复核后保存并绑定条码，不让模型凭空猜营养。
- 日期：云端按 UTC 日历日 `YYYY-MM-DD`；客户端传日期，云端不自行猜测。

## 三、交付门禁（缺一不可）

```bash
# 1. 云端单测
cd C:/Desktop/健康饮食app
node --test tests

# 2. Flutter 静态分析
cd ShiguangFlutter
dart analyze lib

# 3. Flutter 全量测试
flutter test

# 4. release 构建（中文路径用 ASCII 沙盒）
#    沙盒必须复制 android/lib/assets/pubspec.yaml/pubspec.lock/analysis_options.yaml
#    构建后核验 versionName/versionCode/权限/签名/SHA256
```

任何一项失败：先修根因，再重跑；禁止用「应该没问题」收尾。

## 四、新功能落位

- 新云函数路由：`services/<domain>_route.js` + `tests/<domain>-route.test.js`。
- 新纯逻辑：`barcode.js` / `ai_meal.js` / `data/foods.js` 同类模块 + 对应用例。
- 新 Flutter 弹层：`features/record/<name>_flow.dart`，纯换算放 `domain/` 并单测。
- 新全局配置：优先环境变量，其次云端集合；不新增硬编码密钥。
