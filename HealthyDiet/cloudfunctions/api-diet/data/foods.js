/* ============================================================
 * 内置食物库 + 推荐餐（数据与路由分离，便于独立维护/校准）
 * ------------------------------------------------------------
 * 热量/宏量依据《中国食物成分表》第6版 + 包装配料表核算；
 * 有配料表的按标签换算，无标签的查成分表，严禁一刀切估算。
 * meals 字段：适用餐次（breakfast/lunch/dinner/snack），搜索按餐次过滤。
 * per100/baseG：每 100g 营养 + 默认克数，供前端「按克加」换算。
 * ============================================================ */
const BUILTIN_FOODS = [
  // 早餐（protein/carb/fat 单位 g/份）
  { id: "u_01", name: "纯牛奶", meta: "奶类 · 1 盒 250ml", kcal: 175, emoji: "🥛", image: "img/foods/milk.jpg", meals: ["breakfast", "snack"], protein: 8, carb: 12, fat: 9 },
  { id: "u_02", name: "库迪面包", meta: "主食 · 80g", kcal: 256, emoji: "🍞", image: "img/foods/bread.jpg", meals: ["breakfast", "snack"], protein: 7, carb: 44, fat: 4 },
  { id: "u_03", name: "糯玉米", meta: "主食 · 1 根约 250g(可食165g)", kcal: 270, emoji: "🌽", image: "img/foods/corn.jpg", meals: ["breakfast", "snack"], protein: 6, carb: 55, fat: 3 },
  { id: "u_04", name: "煮鸡蛋", meta: "蛋类 · 1 个约 50g", kcal: 78, emoji: "🥚", image: "img/foods/egg.jpg", meals: ["breakfast", "snack"], protein: 7, carb: 1, fat: 5 },
  { id: "u_05", name: "肉包", meta: "主食 · 1 个约 100g", kcal: 230, emoji: "🥟", image: "img/foods/meatbun.jpg", meals: ["breakfast"], protein: 8, carb: 30, fat: 10 },
  // 午餐/晚餐
  { id: "u_06", name: "米饭", meta: "主食 · 1 碗约 150g", kcal: 174, emoji: "🍚", image: "img/foods/rice.jpg", meals: ["lunch", "dinner"], protein: 4, carb: 39, fat: 0, per100: { kcal: 116, protein: 2.6, carb: 25.9, fat: 0.3 }, baseG: 150 },
  { id: "u_07", name: "清炒青菜", meta: "蔬菜 · 1 份约 120g", kcal: 60, emoji: "🥬", image: "img/foods/greens.jpg", meals: ["lunch", "dinner"], protein: 2, carb: 3, fat: 5 },
  { id: "u_08", name: "鸡腿", meta: "禽肉 · 1 个(可食约105g)", kcal: 190, emoji: "🍗", image: "img/foods/chickenleg.jpg", meals: ["lunch", "dinner"], protein: 18, carb: 0, fat: 15 },
  { id: "u_09", name: "鸭腿", meta: "禽肉 · 1 个(可食约105g)", kcal: 240, emoji: "🍗", image: "img/foods/duckleg.jpg", meals: ["lunch", "dinner"], protein: 16, carb: 0, fat: 21 },
  { id: "u_10", name: "芹菜木耳炒蛋", meta: "家常菜 · 1 份约 120g", kcal: 130, emoji: "🍳", image: "img/foods/celeryegg.jpg", meals: ["lunch", "dinner"], protein: 7, carb: 4, fat: 10 },
  { id: "u_11", name: "白切鸡", meta: "禽肉 · 1 份约 120g", kcal: 240, emoji: "🍗", image: "img/foods/whitecut.jpg", meals: ["lunch", "dinner"], protein: 23, carb: 0, fat: 19 },
  { id: "u_12", name: "西兰花炒肉", meta: "家常菜 · 1 份约 130g", kcal: 150, emoji: "🥦", image: "img/foods/broccolipork.jpg", meals: ["lunch", "dinner"], protein: 10, carb: 5, fat: 8 },
  { id: "u_13", name: "胡萝卜炒蛋", meta: "家常菜 · 1 份约 130g", kcal: 140, emoji: "🥕", image: "img/foods/carrotegg.jpg", meals: ["lunch", "dinner"], protein: 7, carb: 7, fat: 9 },
  { id: "u_14", name: "辣椒炒肉", meta: "家常菜 · 1 份约 130g", kcal: 150, emoji: "🌶️", image: "img/foods/chilipork.jpg", meals: ["lunch", "dinner"], protein: 11, carb: 4, fat: 15 },
  { id: "u_15", name: "白切鸭", meta: "禽肉 · 1 份约 140g", kcal: 345, emoji: "🦆", image: "img/foods/whitecutduck.jpg", meals: ["lunch", "dinner"], protein: 22, carb: 0, fat: 28 },
  { id: "u_16", name: "汉堡", meta: "快餐 · 1 个约 200g", kcal: 500, emoji: "🍔", image: "img/foods/burger.jpg", meals: ["lunch", "dinner"], protein: 22, carb: 42, fat: 25 },
  { id: "u_17", name: "鸡块", meta: "快餐 · 3 个约 48g", kcal: 140, emoji: "🍗", image: "img/foods/nuggets.jpg", meals: ["lunch", "dinner"], protein: 7, carb: 8, fat: 9 },
  { id: "u_18", name: "可乐", meta: "饮品 · 200ml", kcal: 86, emoji: "🥤", image: "img/foods/cola.jpg", meals: ["lunch", "dinner"], protein: 0, carb: 21, fat: 0 },
  { id: "u_22", name: "沙县鸭腿饭", meta: "快餐 · 1 份(饭+鸭腿+菜)", kcal: 750, emoji: "🍱", image: "img/foods/shaxian.jpg", meals: ["lunch", "dinner"], protein: 27, carb: 72, fat: 39 },
  { id: "u_23", name: "黄瓜炒火腿肠", meta: "家常菜 · 1 份约 135g", kcal: 167, emoji: "🥒", image: "img/foods/cucumberham.jpg", meals: ["lunch", "dinner"], protein: 7, carb: 10, fat: 11 },
  { id: "u_24", name: "炒西蓝花", meta: "蔬菜 · 1 份约 135g", kcal: 86, emoji: "🥦", image: "img/foods/broccoli.jpg", meals: ["lunch", "dinner"], protein: 3, carb: 5, fat: 6 },
  { id: "u_25", name: "葱姜鸡", meta: "粤菜 · 1 份约 135g", kcal: 266, emoji: "🐔", image: "img/foods/congjiangji.jpg", meals: ["lunch", "dinner"], protein: 23, carb: 3, fat: 18 },
  { id: "u_26", name: "饼干", meta: "零食 · 1 块约 35g", kcal: 152, emoji: "🍪", image: "img/foods/biscuit.jpg", meals: ["breakfast", "snack"], protein: 3.2, carb: 25.1, fat: 4.4, per100: { kcal: 435, protein: 9, carb: 71.7, fat: 12.7 }, baseG: 35 },
  { id: "u_27", name: "泡面", meta: "主食 · 1 桶面饼+配料 128g", kcal: 600, emoji: "🍜", image: "img/foods/cupnoodle.jpg", meals: ["lunch", "dinner"], protein: 10.5, carb: 76.8, fat: 27.8, per100: { kcal: 469, protein: 8.2, carb: 60, fat: 21.7 }, baseG: 128 },
  { id: "u_28", name: "啤酒", meta: "饮品 · 500ml(能量含酒精)", kcal: 170, emoji: "🍺", image: "img/foods/beer.jpg", meals: ["lunch", "dinner", "snack"], protein: 2, carb: 18, fat: 0, per100: { kcal: 34, protein: 0.4, carb: 3.6, fat: 0 }, baseG: 500 },
  { id: "u_29", name: "咸鸭蛋", meta: "蛋类 · 1 个约 50g", kcal: 95, emoji: "🥚", image: "img/foods/saltedegg.jpg", meals: ["breakfast", "lunch", "dinner"], protein: 6.4, carb: 3.2, fat: 6.4, per100: { kcal: 190, protein: 12.7, carb: 6.3, fat: 12.7 }, baseG: 50 },
  // 比比赞面包：配料表 100g = 1464kJ / 蛋白 9.0g / 脂肪 10.8g（50g 为其一半）；碳水按能量守恒反推 54.2g
  { id: "u_30", name: "比比赞面包", meta: "主食 · 每 50g", kcal: 175, emoji: "🍞", image: "img/foods/bibizanbread.jpg", meals: ["breakfast", "snack"], protein: 4.5, carb: 27.1, fat: 5.4, per100: { kcal: 350, protein: 9, carb: 54.2, fat: 10.8 }, baseG: 50 },
  // 零食/饮品
  { id: "u_19", name: "冰红茶", meta: "饮品 · 500ml", kcal: 190, emoji: "🧋", image: "img/foods/icetea.jpg", meals: ["snack"], protein: 0, carb: 47, fat: 0 },
  { id: "u_20", name: "可乐", meta: "饮品 · 500ml", kcal: 215, emoji: "🥤", image: "img/foods/cola.jpg", meals: ["snack"], protein: 0, carb: 53, fat: 0 },
  { id: "u_21", name: "奶茶", meta: "饮品 · 1 杯约 500ml(5分糖)", kcal: 400, emoji: "🧋", image: "img/foods/milktea.jpg", meals: ["snack"], protein: 6, carb: 62, fat: 14 },
];

const RECOMMENDATIONS = [
  { id: "m_01", name: "牛油果鸡蛋全麦堡", kcal: 368, tag: "早餐 · 10 分钟", emoji: "🥑", macros: { carb: 34, protein: 18, fat: 19 } },
  { id: "m_02", name: "茄汁虾仁烩糙饭", kcal: 412, tag: "晚餐 · 高蛋白", emoji: "🍤", macros: { carb: 46, protein: 32, fat: 10 } },
  { id: "m_03", name: "酸奶燕麦果粒杯", kcal: 295, tag: "加餐 · 免烹饪", emoji: "🥣", macros: { carb: 38, protein: 14, fat: 9 } }
];

module.exports = { BUILTIN_FOODS, RECOMMENDATIONS };
