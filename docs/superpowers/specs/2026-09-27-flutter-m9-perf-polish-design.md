# M9 设计——性能 SWR 缓存 + Flutter 质感批

日期：2026-09-27 ｜ 里程碑：M9 ｜ 版本目标：2.7.0+20700 ｜ 分支：feat/flutter-m9-perf-polish
提出：老大真机使用反馈（09-27）「数据/食物库加载慢，交互和样式高级一点，发挥 Flutter 特点」；范围裁定「全干」（A+B 全收，含 SWR 旧数闪现盲区知情通过）。

## 0. 诊断基线（事实，当场实测）

- 网关短连实测：`/foods/builtin` 0.44-0.56s、`/foods/custom` 0.43s、`/diary/summary` 0.38-0.43s；冷热差 <0.15s，无冷启动尖峰。**单次网络往返 ~400ms 是地板，云函数不是瓶颈。**
- 慢因（代码实锤）：①食物库内置缓存 `_builtinCache` 挂弹层 State（food_lib_sheet.dart:212-216），弹层销毁即失效→每次重开白屏重拉；②自定义列表同样每次重拉、切 tab 再拉一轮；③加载期是「加载中…」纯文字白屏，400ms 空窗全暴露。
- 预测标注：SWR 落地后「重开弹层」体感 400ms→0ms 出画面（后台刷新）；首次进入仍 ~400ms（无缓存可用），属预期。

## 1. A1——会话级 SWR 缓存层

**形态**：新文件 `lib/data/swr_cache.dart`。

```dart
/// 会话级内存缓存（生命周期=ProviderContainer=一次启动会话；进程杀重开自然失效，
/// 不做磁盘持久化——避开序列化/过期策略复杂度，YAGNI）。
class SwrCache {
  final _store = <String, Object?>{};
  T? read<T>(String key) => _store[key] is T ? _store[key] as T : null;
  void write(String key, Object? value) => _store[key] = value;
  void invalidate(String key) => _store.remove(key);
  void invalidatePrefix(String prefix) =>
      _store.removeWhere((k, _) => k.startsWith(prefix));
  void clear() => _store.clear();
}
final swrCacheProvider = Provider<SwrCache>((ref) => SwrCache());
```

**接入面（只接高频读，搜索/写后回读不缓存）**：

| 缓存键 | provider | 失效点（写操作主动 invalidate） |
|---|---|---|
| `builtin` | getBuiltinFoods（食物库内置 tab + 记录页内置搜索的库源） | 无写路径（云端硬编码）——会话内永不失效 |
| `custom` | listCustomFoods（食物库自定义 tab） | addCustomFood/deleteCustomFood/setCustomFoodMeals |
| `summary.<date>` | summaryProvider(date) | 记餐/删餐（record_controller 双删链）；setGoal 整族；重试钮（先删键再 invalidate） |
| `records.<date>` | recordsProvider(date) | 记餐/删餐（同上）；重试钮 |
| `exercises.<date>` | exercisesProvider(date) | addExercise/remove 回滚链（_reload 成功回写/失败清键） |
| `weightTrend` | weightTrendProvider | logWeight（体重卡保存链） |

（喝水不单设键——water 字段在 summary 内，随 `summary.<date>` 同进同出；`waterOverrideProvider` 本地乐观态维持现状不缓存。）

> **终审勘误（09-27，SDD 台账 Ruling 汇总）**：原表把「喝水/记运动/删运动」列为 summary/records 失效点系作者误设——运动消耗是端侧 exerciseKcalProvider fold 派生（advice.dart:176 / plate_ring.dart:81），运动写不碰 summary 云面；喝水走 waterOverride 本地态、H5 亦不重拉 summary（T2 裁定），三行已按实际实现改记。custom 行原括注「每次开层重取」与 H5 app.js:1308 逐字铁律冲突（T4 裁定：开层命中短路、切 tab 真重取为唯一自洽解）。

**SWR 语义（每个接入 provider 统一模式）**：build 时 `cache.read(key)` 命中 → 先 `state = AsyncData(cached)` 且**继续发网络请求**，回包后 `state = AsyncData(fresh)` + 回写缓存；未命中 → 走现行 loading→data。失败支：有缓存 → 保缓存不炸 error 卡（后台静默失败不打扰，下次操作再试，登记差异）；无缓存 → 现行 error。

**行为差异登记（老大已批）**：切日期/重开弹层先显旧数、≤400ms 内跳新数——与 H5「白屏等回包」的逐字口径在**呈现时序**上分叉（数据终态一致）。R4 铁律覆盖数据行为，此为呈现层自主位（同 toast 时长 2400ms 先例）。

**换号/登出**：auth_state 失效清单补 `swrCache.clear()`（经 ref.read 在 invalidate 波次里执行；keepAlive Provider 不随 autoDispose 波次走，必须显式清）。

**测试钉**：①首开 loading→data 且回写；②重开先 data(旧) 后台刷新到 data(新)；③写操作后键失效（下次拉新）；④换号全清；⑤失败有缓存不显 error。

## 2. A2——加载白屏换骨架

- food_lib_sheet `加载中…`（:453-457）→ 3 行卡形灰条骨架（复用 home `_MealSkeletonRow` 定式升为公共组件 `SkeletonBar`，放 `lib/features/common/skeleton.dart`）。
- home `_PlateRingSkeleton` 的「加载中」文字、water_card「加载中」→ 保留（有骨架形，仅去文字，减噪）。
- 有 A1 后骨架只在**会话首访**出现，概率大降，本项是兜底观感。

## 3. A3——食物库弹层双列表并行

open 时 `Future.wait([listCustomFoods, getBuiltinFoods])` 一次拉双（各走 A1 缓存判断，命中侧不发请求）；切 tab 零等待。

## 4. B 质感批（视觉层，R4 自主；全部不触碰数据语义）

**B1 按压反馈**：新组件 `lib/features/common/pressable.dart`——`PressableScale(onTap, child)`：GestureDetector 监听 tapDown/up/cancel，AnimatedScale 1.0→0.975（120ms easeOut）→回弹（250ms elasticOut）。覆盖面（高价值位，不铺全量）：首页四卡、食物库/运动/喝水弹层行、弹层主按钮、记录页餐次 chip。
**B2 错峰入场**：新组件 `lib/features/common/stagger.dart`——`Stagger(index:i, child:...)`：首次 build 播 translateY(14)+fade，220ms easeOutCubic，delay 40ms×i；**只播一次**（State 布尔），数据刷新/切日期 rebuild 不重播（避免回访骚扰）；页面重开（provider 重建）重播属预期。覆盖：首页卡序、报告页卡序、食物库列表行（首屏前 8 行）。
**B3 环数插值升级**：plate_ring 中心数 IntTween 改「从上一值→新值」（didUpdateWidget 记旧值；首帧仍 0→值）；环弧 Tween 曲线加微弹（easeOutBack c1=1.2，避免过冲遮挡）。测试注：pumpAndSettle 到终值，断言零改。
**B4 弹层统一 handle 化**：新 helper `showShiguangSheet(context, {title, child})` 收口 11 处 showModalBottomSheet 的重复样板（shape/背景/标题行+✕ 定式已在四处复制）：顶部 drag handle（28×4 圆条 surfaceSoft）、isScrollControlled:true、内容区最大高 78%、下拉跟手关闭（BottomSheet 默认拖拽行为，外层包 Padding(MediaQuery.viewInsets) 保留键盘避让）。✕ 钮保留（H5 哨兵测试依赖）。**只收样板，不弹层内业务 widget 零改动**。
**B5 toast 动效**：主题实位——SnackBarThemeData 只有 `enterAnimationCurve/exitAnimationCurve` 可调（动画类型不可换），入场曲线改 `Curves.easeOutBack`（微过冲上浮感）、出场 150ms 级快收（exit curve easeInCubic）。35 处调用点的 `showSgToast` helper 收敛（可带 animationStyle 做 scale/slide）登记为后续池，本批不做（避免与 M7 后续池 confirmSheet 三复制重复计工）。
**B6 tab 切页过渡**：不引入 PageTransitionSwitcher（过度工程）——并入 B2：切 tab 后目标页卡片走一次错峰入场（PageView 常驻页首次 build 已播；回访不重播的 B2 语义下，tab 往返无重播=正确克制）。**登记为「B6 以 B2 语义达成，无独立代码」**。

## 5. 不做清单（YAGNI/边界）

- 磁盘持久化缓存（会话级足够；跨启动新鲜度优先）。
- 搜索关键词缓存（本就要求实时）。
- 云函数侧改动（实测不是瓶颈，不动 api-diet）。
- 全屏 hero 转场/共享元素（无对应场景）。
- H5 线不动（本批纯 Flutter）。

## 6. 版本与门禁

2.7.0+20700；四门禁（dart analyze / flutter test / H5 node --test / check:version）；ASCII 沙盒 release 重打 + 验签基线；真机目检（弹层重开速度对比、骨架、按压/入场/环动效、toast、11 弹层 handle 抽查 3 个）；互通抽查不变（云端数据面零改动）。

## 7. 风险与回退

- SWR 失效点遗漏 → 显旧数据不刷新：以「写路径全表盘点」进计划逐条钉（上表失效矩阵为验收基线）；真机复验各写路径后回读。
- B2 只播一次的「首帧」判定在 ListView 回收重建下误播：Stagger 记 key 集合在 State（页面级），回收重建不重播。
- PressableScale 与既有 GestureDetector 嵌套冲突：只包无内部手势的容器位；行内钮（✕/删除）保持自身手势不包。
- 弹层 handle 化触碰 11 处弹层测试：helper 保留原结构（标题/✕/内容 slot），测试选择器不破坏；每收一处跑该弹层测试文件。
