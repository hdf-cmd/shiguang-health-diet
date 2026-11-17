/* ============================================================
 * 内置食物库 + 推荐餐（数据与路由分离，便于独立维护/校准）
 * ------------------------------------------------------------
 * 热量/宏量依据《中国食物成分表》第6版 + 包装配料表核算；
 * 有配料表的按标签换算，无标签的查成分表，严禁一刀切估算。
 * meals 字段：适用餐次（breakfast/lunch/dinner/snack），搜索按餐次过滤。
 *   归类原则（2026-09-15 校准）：正餐 lunch/dinner = 饭菜肉蛋面等正餐场景；
 *   早餐 breakfast = 早餐主食/奶蛋；零食 snack = 饮品/点心/小吃——**饮料一律归零食，不进正餐**；
 *   面包类归「早餐 + 零食」（不当正餐）。新增食物按此原则标注。
 * per100/baseG：每 100g 营养 + 默认克数，供前端「按克加」换算。
 *   单一食材/标签食品按成分表/配料表直查；复合菜（炒菜/快餐组合）
 *   按「整份均质」口径核算——per100 = 整份值 ÷ 整份可食克数，
 *   按克加假定油/配料与份量等比放大，估算值 meta 一律带「约」。
 *   baseG 是弹层默认克数（老大 2026-09-19 定的食堂口径：米饭 200g、
 *   菜 160g），不必等于整份核算用的克数（meta 里的「1 份约 Xg」）。
 * ============================================================ */
const BUILTIN_FOODS = [
  // 早餐（protein/carb/fat 单位 g/份）
  { id: "u_01", name: "纯牛奶", meta: "奶类 · 1 盒 250ml", kcal: 175, emoji: "🥛", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/milk.jpg", meals: ["breakfast", "snack"], protein: 8, carb: 12, fat: 9, per100: { kcal: 70, protein: 3.2, carb: 4.8, fat: 3.6 }, baseG: 250 },
  { id: "u_02", name: "库迪面包", meta: "主食 · 80g", kcal: 256, emoji: "🍞", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/bread.jpg", meals: ["breakfast", "snack"], protein: 7, carb: 44, fat: 4, per100: { kcal: 320, protein: 8.8, carb: 55, fat: 5 }, baseG: 80 },
  { id: "u_03", name: "糯玉米", meta: "主食 · 1 根约 250g(可食165g)", kcal: 270, emoji: "🌽", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/corn.jpg", meals: ["breakfast", "snack"], protein: 6, carb: 55, fat: 3, per100: { kcal: 164, protein: 3.6, carb: 33.3, fat: 1.8 }, baseG: 165 },
  { id: "u_04", name: "煮鸡蛋", meta: "蛋类 · 1 个约 50g", kcal: 78, emoji: "🥚", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/egg.jpg", meals: ["breakfast", "snack"], protein: 7, carb: 1, fat: 5, per100: { kcal: 156, protein: 14, carb: 2, fat: 10 }, baseG: 50 },
  { id: "u_05", name: "肉包", meta: "主食 · 1 个约 100g", kcal: 230, emoji: "🥟", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/meatbun.jpg", meals: ["breakfast"], protein: 8, carb: 30, fat: 10, per100: { kcal: 230, protein: 8, carb: 30, fat: 10 }, baseG: 100 },
  // 午餐/晚餐
  { id: "u_06", name: "米饭", meta: "主食 · 1 碗约 150g", kcal: 174, emoji: "🍚", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/rice.jpg", meals: ["lunch", "dinner"], protein: 4, carb: 39, fat: 0, per100: { kcal: 116, protein: 2.6, carb: 25.9, fat: 0.3 }, baseG: 200 },
  { id: "u_07", name: "清炒青菜", meta: "蔬菜 · 1 份约 120g", kcal: 60, emoji: "🥬", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/greens.jpg", meals: ["lunch", "dinner"], protein: 2, carb: 3, fat: 5, per100: { kcal: 50, protein: 1.7, carb: 2.5, fat: 4.2 }, baseG: 160 },
  { id: "u_08", name: "鸡腿", meta: "禽肉 · 1 个(可食约105g)", kcal: 190, emoji: "🍗", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/chickenleg.jpg", meals: ["lunch", "dinner"], protein: 18, carb: 0, fat: 15, per100: { kcal: 181, protein: 17.1, carb: 0, fat: 14.3 }, baseG: 105 },
  { id: "u_09", name: "鸭腿", meta: "禽肉 · 1 个(可食约105g)", kcal: 240, emoji: "🍗", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/duckleg.jpg", meals: ["lunch", "dinner"], protein: 16, carb: 0, fat: 21, per100: { kcal: 229, protein: 15.2, carb: 0, fat: 20 }, baseG: 105 },
  { id: "u_10", name: "芹菜木耳炒蛋", meta: "家常菜 · 1 份约 120g", kcal: 130, emoji: "🍳", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/celeryegg.jpg", meals: ["lunch", "dinner"], protein: 7, carb: 4, fat: 10, per100: { kcal: 108, protein: 5.8, carb: 3.3, fat: 8.3 }, baseG: 160 },
  { id: "u_11", name: "白切鸡", meta: "禽肉 · 1 份约 120g", kcal: 240, emoji: "🍗", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/whitecut.jpg", meals: ["lunch", "dinner"], protein: 23, carb: 0, fat: 19, per100: { kcal: 200, protein: 19.2, carb: 0, fat: 15.8 }, baseG: 160 },
  { id: "u_12", name: "西兰花炒肉", meta: "家常菜 · 1 份约 130g", kcal: 150, emoji: "🥦", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/broccolipork.jpg", meals: ["lunch", "dinner"], protein: 10, carb: 5, fat: 8, per100: { kcal: 115, protein: 7.7, carb: 3.8, fat: 6.2 }, baseG: 160 },
  { id: "u_13", name: "胡萝卜炒蛋", meta: "家常菜 · 1 份约 130g", kcal: 140, emoji: "🥕", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/carrotegg.jpg", meals: ["lunch", "dinner"], protein: 7, carb: 7, fat: 9, per100: { kcal: 108, protein: 5.4, carb: 5.4, fat: 6.9 }, baseG: 160 },
  { id: "u_14", name: "辣椒炒肉", meta: "家常菜 · 1 份约 130g", kcal: 150, emoji: "🌶️", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/chilipork.jpg", meals: ["lunch", "dinner"], protein: 11, carb: 4, fat: 15, per100: { kcal: 115, protein: 8.5, carb: 3.1, fat: 11.5 }, baseG: 160 },
  { id: "u_15", name: "白切鸭", meta: "禽肉 · 1 份约 140g", kcal: 345, emoji: "🦆", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/whitecutduck.jpg", meals: ["lunch", "dinner"], protein: 22, carb: 0, fat: 28, per100: { kcal: 246, protein: 15.7, carb: 0, fat: 20 }, baseG: 160 },
  { id: "u_16", name: "汉堡", meta: "快餐 · 1 个约 200g", kcal: 500, emoji: "🍔", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/burger.jpg", meals: ["lunch", "dinner"], protein: 22, carb: 42, fat: 25, per100: { kcal: 250, protein: 11, carb: 21, fat: 12.5 }, baseG: 200 },
  { id: "u_17", name: "鸡块", meta: "快餐 · 3 个约 48g", kcal: 140, emoji: "🍗", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/nuggets.jpg", meals: ["lunch", "dinner"], protein: 7, carb: 8, fat: 9, per100: { kcal: 292, protein: 14.6, carb: 16.7, fat: 18.8 }, baseG: 48 },
  { id: "u_18", name: "可乐", meta: "饮品 · 200ml", kcal: 86, emoji: "🥤", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/cola.jpg", meals: ["snack"], protein: 0, carb: 21, fat: 0, per100: { kcal: 43, protein: 0, carb: 10.5, fat: 0 }, baseG: 200 },
  { id: "u_22", name: "沙县鸭腿饭", meta: "快餐 · 1 份约 450g(饭+鸭腿+菜)", kcal: 750, emoji: "🍱", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/shaxian.jpg", meals: ["lunch", "dinner"], protein: 27, carb: 72, fat: 39, per100: { kcal: 167, protein: 6, carb: 16, fat: 8.7 }, baseG: 450 },
  { id: "u_23", name: "黄瓜炒火腿肠", meta: "家常菜 · 1 份约 135g", kcal: 167, emoji: "🥒", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/cucumberham.jpg", meals: ["lunch", "dinner"], protein: 7, carb: 10, fat: 11, per100: { kcal: 124, protein: 5.2, carb: 7.4, fat: 8.1 }, baseG: 160 },
  { id: "u_24", name: "炒西蓝花", meta: "蔬菜 · 1 份约 135g", kcal: 86, emoji: "🥦", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/broccoli.jpg", meals: ["lunch", "dinner"], protein: 3, carb: 5, fat: 6, per100: { kcal: 64, protein: 2.2, carb: 3.7, fat: 4.4 }, baseG: 160 },
  { id: "u_25", name: "葱姜鸡", meta: "粤菜 · 1 份约 135g", kcal: 266, emoji: "🐔", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/congjiangji.jpg", meals: ["lunch", "dinner"], protein: 23, carb: 3, fat: 18, per100: { kcal: 197, protein: 17, carb: 2.2, fat: 13.3 }, baseG: 160 },
  { id: "u_26", name: "饼干", meta: "零食 · 1 块约 35g", kcal: 152, emoji: "🍪", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/biscuit.jpg", meals: ["breakfast", "snack"], protein: 3.2, carb: 25.1, fat: 4.4, per100: { kcal: 435, protein: 9, carb: 71.7, fat: 12.7 }, baseG: 35 },
  { id: "u_27", name: "泡面", meta: "主食 · 1 桶面饼+配料 128g", kcal: 600, emoji: "🍜", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/cupnoodle.jpg", meals: ["lunch", "dinner"], protein: 10.5, carb: 76.8, fat: 27.8, per100: { kcal: 469, protein: 8.2, carb: 60, fat: 21.7 }, baseG: 128 },
  { id: "u_28", name: "啤酒", meta: "饮品 · 500ml(能量含酒精)", kcal: 170, emoji: "🍺", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/beer.jpg", meals: ["snack"], protein: 2, carb: 18, fat: 0, per100: { kcal: 34, protein: 0.4, carb: 3.6, fat: 0 }, baseG: 500 },
  { id: "u_29", name: "咸鸭蛋", meta: "蛋类 · 1 个约 50g", kcal: 95, emoji: "🥚", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/saltedegg.jpg", meals: ["breakfast", "lunch", "dinner"], protein: 6.4, carb: 3.2, fat: 6.4, per100: { kcal: 190, protein: 12.7, carb: 6.3, fat: 12.7 }, baseG: 50 },
  { id: "u_36", name: "鸡蛋", meta: "蛋类 · 1 个约 50g", kcal: 78, emoji: "🥚", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/egg.jpg", meals: ["breakfast", "lunch", "dinner", "snack"], protein: 7, carb: 1, fat: 5, per100: { kcal: 156, protein: 14, carb: 2, fat: 10 }, baseG: 50 },
  // 比比赞面包：配料表 100g = 1464kJ / 蛋白 9.0g / 脂肪 10.8g（50g 为其一半）；碳水按能量守恒反推 54.2g
  { id: "u_30", name: "比比赞面包", meta: "主食 · 每 50g", kcal: 175, emoji: "🍞", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/bibizanbread.jpg", meals: ["breakfast", "snack"], protein: 4.5, carb: 27.1, fat: 5.4, per100: { kcal: 350, protein: 9, carb: 54.2, fat: 10.8 }, baseG: 50 },
  // 2026-09-15 古茗系列+家常菜 5 条：佛卡夏热量按用户给的宏量算（12×4+7×9+26×4=215）；柠檬水/抹茶茶酥按用户标签；鸡蛋羹/肉饼蒸蛋为常见估值（拿到配料表后应校准）
  { id: "u_31", name: "古茗酸黄瓜牛肉佛卡夏", meta: "轻食 · 1 份约 100g", kcal: 215, emoji: "🥪", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/gumingfocaccia.jpg", meals: ["breakfast", "snack"], protein: 12, carb: 26, fat: 7, per100: { kcal: 215, protein: 12, carb: 26, fat: 7 }, baseG: 100 },
  { id: "u_32", name: "古茗柠檬水", meta: "饮品 · 1 杯 500ml", kcal: 125, emoji: "🍋", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/guminglemontea.jpg", meals: ["snack"], protein: 0, carb: 32, fat: 0, per100: { kcal: 25, protein: 0, carb: 6.4, fat: 0 }, baseG: 500 },
  { id: "u_33", name: "古茗抹茶茶酥", meta: "零食 · 1 个约 10g", kcal: 48, emoji: "🍵", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/gumingmatchacrisp.jpg", meals: ["snack", "breakfast"], protein: 1, carb: 5.5, fat: 2.5, per100: { kcal: 480, protein: 10, carb: 55, fat: 25 }, baseG: 10 },
  { id: "u_34", name: "鸡蛋羹", meta: "家常菜 · 1 碗约 130g", kcal: 65, emoji: "🥚", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/jidangeng.jpg", meals: ["lunch", "dinner"], protein: 5, carb: 1.5, fat: 4, per100: { kcal: 50, protein: 3.8, carb: 1.2, fat: 3.1 }, baseG: 160 },
  { id: "u_35", name: "肉饼蒸蛋", meta: "家常菜 · 1 碗约 150g", kcal: 210, emoji: "🥘", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/roubingzhengdan.jpg", meals: ["lunch", "dinner"], protein: 15, carb: 4, fat: 15, per100: { kcal: 140, protein: 10, carb: 2.7, fat: 10 }, baseG: 160 },
  // 零食/饮品（按克加时 1ml≈1g，直接填毫升数即可）
  { id: "u_19", name: "冰红茶", meta: "饮品 · 500ml", kcal: 190, emoji: "🧋", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/icetea.jpg", meals: ["snack"], protein: 0, carb: 47, fat: 0, per100: { kcal: 38, protein: 0, carb: 9.4, fat: 0 }, baseG: 500 },
  { id: "u_20", name: "可乐", meta: "饮品 · 500ml", kcal: 215, emoji: "🥤", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/cola.jpg", meals: ["snack"], protein: 0, carb: 53, fat: 0, per100: { kcal: 43, protein: 0, carb: 10.6, fat: 0 }, baseG: 500 },
  { id: "u_21", name: "奶茶", meta: "饮品 · 1 杯约 500ml(5分糖)", kcal: 400, emoji: "🧋", image: "https://cloud1-d6g4x9h9m507b429c-1474880521.tcloudbaseapp.com/img/foods/milktea.jpg", meals: ["snack"], protein: 6, carb: 62, fat: 14, per100: { kcal: 80, protein: 1.2, carb: 12.4, fat: 2.8 }, baseG: 500 },
];

const RECOMMENDATIONS = [
  { id: "m_01", name: "牛油果鸡蛋全麦堡", kcal: 368, tag: "早餐 · 10 分钟", emoji: "🥑", macros: { carb: 34, protein: 18, fat: 19 } },
  { id: "m_02", name: "茄汁虾仁烩糙饭", kcal: 412, tag: "晚餐 · 高蛋白", emoji: "🍤", macros: { carb: 46, protein: 32, fat: 10 } },
  { id: "m_03", name: "酸奶燕麦果粒杯", kcal: 295, tag: "加餐 · 免烹饪", emoji: "🥣", macros: { carb: 38, protein: 14, fat: 9 } }
];

module.exports = { BUILTIN_FOODS, RECOMMENDATIONS };
