// ShiguangFlutter/test/domain/report_test.dart
// 逐字移植自 H5 js/app.js：
//   日均 renderWeekReport:802-803（recorded=kcal.filter(v>0)，avg=Math.round(sum/(len||1))）
//   期间建议 buildPeriodAdvice:833-843（5 规则顺序 push + slice(0,3).join('；')+'。'）
//   今日索引 renderWeekReport:792-793（getDay 0=日 → 周一=0…周日=6）
// 裁定 R2：云端 rates 封顶 100（api-diet/index.js:492），carb>110 / fat>110 两规则
// 在真实数据下不可达（死分支）。本测试构造 >110 边界样本仅登记保真行为，禁止"修正"。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/report.dart';

/// 构造期间建议用报告数据：默认全部落在"不触发"区间
/// （蛋白 80-100、碳水 60-110、脂肪 ≤110、日均 0.7×目标 ≤ avg ≤ 目标）
ReportData adviceData({
  int carbRate = 80,
  int proteinRate = 90,
  int fatRate = 90,
  int target = 1000,
}) =>
    ReportData(
      labels: const ['一', '二', '三', '四', '五', '六', '日'],
      kcal: const [800, 800],
      target: target,
      carbRate: carbRate,
      proteinRate: proteinRate,
      fatRate: fatRate,
      isWeek: true,
      recordedDays: 2,
      total: 1600,
    );

void main() {
  group('avgRecorded（js/app.js:802-803）', () {
    test('只算 >0 天：[0,100,200] → round(300/2)=150', () {
      expect(avgRecorded([0, 100, 200]), 150);
    });
    test('空数组分母按 1：[] → round(0/1)=0', () {
      expect(avgRecorded([]), 0);
    });
    test('单日：[75] → 75', () {
      expect(avgRecorded([75]), 75);
    });
    test('小数和走 jsRound（V8 Math.round 语义）：[100,101] → 201/2=100.5 → 101', () {
      expect(avgRecorded([100, 101]), 101);
    });
    test('0 不参与分母：[0,0,300] → round(300/1)=300', () {
      expect(avgRecorded([0, 0, 300]), 300);
    });
  });

  group('periodAdvice（js/app.js:833-843，规则顺序不得调换）', () {
    test('蛋白 <80 触发，文案逐字', () {
      expect(
          periodAdvice(adviceData(proteinRate: 70), 800),
          '蛋白质达标率 70%，偏低，每餐加一份鱼、虾、蛋或豆制品。');
    });

    test('碳水 60–110 区间不触发：60 与 110 边界都走兜底句', () {
      const fallback = '三餐节奏稳定，营养素都在合理区间，继续保持，把运动打卡也安排上。';
      expect(periodAdvice(adviceData(carbRate: 60), 800), fallback);
      expect(periodAdvice(adviceData(carbRate: 110), 800), fallback);
    });

    test('碳水 <60 触发，文案逐字', () {
      expect(
          periodAdvice(adviceData(carbRate: 50), 800),
          '碳水达标率 50%，偏低，主食不足易乏力，保留适量谷物。');
    });

    test('R2 死分支保真：碳水 >110 触发（真实数据不可达，bug-for-bug 保留）', () {
      expect(
          periodAdvice(adviceData(carbRate: 111), 800),
          '碳水达目标 111%，偏高，主食可换粗粮或减两成。');
    });

    test('R2 死分支保真：脂肪 >110 触发（真实数据不可达，bug-for-bug 保留）；110 不触发', () {
      expect(
          periodAdvice(adviceData(fatRate: 111), 800),
          '脂肪达目标 111%，偏高，少油炸、多蒸煮拌。');
      expect(periodAdvice(adviceData(fatRate: 110), 800),
          '三餐节奏稳定，营养素都在合理区间，继续保持，把运动打卡也安排上。');
    });

    test('日均超目标触发，差值插值逐字', () {
      expect(
          periodAdvice(adviceData(), 1150),
          '日均 1150 kcal 超目标 1000 kcal，想控重每日减 150 kcal 左右。');
    });

    test('日均 >0 且 <0.7×目标触发；等于 0.7×目标不触发；日均 0 不触发', () {
      expect(
          periodAdvice(adviceData(target: 1000), 699),
          '日均 699 kcal 明显低于目标，长期吃太少会掉代谢，适当吃够。');
      // avg=700 = 0.7*1000：严格小于才触发
      expect(periodAdvice(adviceData(target: 1000), 700),
          '三餐节奏稳定，营养素都在合理区间，继续保持，把运动打卡也安排上。');
      // 整周未记录（avg=0）：0 > 0 为假，不触发低热量句
      expect(periodAdvice(adviceData(target: 1000), 0),
          '三餐节奏稳定，营养素都在合理区间，继续保持，把运动打卡也安排上。');
    });

    test('top3 截断依赖 push 顺序：4 条触发只保留前 3 条，以"。"结尾', () {
      // 按源码顺序：蛋白 → 碳水(死) → 脂肪(死) → 热量，第 4 条（超目标）被截掉
      final r = adviceData(proteinRate: 70, carbRate: 111, fatRate: 111);
      expect(
          periodAdvice(r, 1150),
          '蛋白质达标率 70%，偏低，每餐加一份鱼、虾、蛋或豆制品；'
          '碳水达目标 111%，偏高，主食可换粗粮或减两成；'
          '脂肪达目标 111%，偏高，少油炸、多蒸煮拌。');
    });
  });

  group('parseWeekReport（云函数 /report/week 返回）', () {
    test('fixture 全字段：days→labels、isWeek=true、recordedDays/total 由 kcal 推', () {
      final r = parseWeekReport({
        'days': ['一', '二', '三', '四', '五', '六', '日'],
        'kcal': [1200, 0, 1500, 1800, 0, 2000, 900],
        'target': 1800,
        'rates': {'carb': 85, 'protein': 70, 'fat': 95},
      });
      expect(r.labels, ['一', '二', '三', '四', '五', '六', '日']);
      expect(r.kcal, [1200, 0, 1500, 1800, 0, 2000, 900]);
      expect(r.target, 1800);
      expect(r.carbRate, 85);
      expect(r.proteinRate, 70);
      expect(r.fatRate, 95);
      expect(r.isWeek, true);
      expect(r.recordedDays, 5); // >0 计数
      expect(r.total, 7400); // fold 求和
      expect(r.avgText, isNull); // 周报无月均文案
    });

    test('json 数字为 num（可能是 double）时取整不崩', () {
      final r = parseWeekReport({
        'days': ['一'],
        'kcal': [1500.0, 0],
        'target': 1800.0,
        'rates': {'carb': 80.0, 'protein': 70.0, 'fat': 90.0},
      });
      expect(r.kcal, [1500, 0]);
      expect(r.target, 1800);
      expect(r.carbRate, 80);
      expect(r.recordedDays, 1);
      expect(r.total, 1500);
    });
  });

  group('parseMonthReport（云函数 /report/month 返回）', () {
    test('fixture 全字段：weeks→labels、isWeek=false、days/total 直读、avgText 由调用方注入', () {
      final r = parseMonthReport({
        'weeks': ['W1', 'W2', 'W3', 'W4'],
        'kcal': [1600, 0, 1750, 1900],
        'target': 1800,
        'days': 18,
        'total': 30500,
        'rates': {'carb': 88, 'protein': 76, 'fat': 92},
        'isWeek': false,
      });
      expect(r.labels, ['W1', 'W2', 'W3', 'W4']);
      expect(r.kcal, [1600, 0, 1750, 1900]);
      expect(r.target, 1800);
      expect(r.carbRate, 88);
      expect(r.proteinRate, 76);
      expect(r.fatRate, 92);
      expect(r.isWeek, false);
      expect(r.recordedDays, 18); // 月报 days=有记录天数
      expect(r.total, 30500);
      expect(r.avgText, isNull); // parse 不生成月均文案（Task 5 控制器拼）
    });

    test('avgText 传入时透传（对应 H5 {...r, avgText} 注入路径）', () {
      final r = parseMonthReport({
        'weeks': ['W1'],
        'kcal': [1600],
        'target': 1800,
        'days': 5,
        'total': 8000,
        'rates': {'carb': 80, 'protein': 80, 'fat': 80},
        'avgText': '月均 1600 kcal · 记 5 天',
      });
      expect(r.avgText, '月均 1600 kcal · 记 5 天');
    });
  });

  group('weekTodayIndex（js/app.js:792-793 getDay 换算：周一=0…周日=6）', () {
    test('2026-09-21 是周一 → 0', () {
      expect(weekTodayIndex(DateTime(2026, 9, 21)), 0);
    });
    test('2026-09-27 是周日 → 6', () {
      expect(weekTodayIndex(DateTime(2026, 9, 27)), 6);
    });
    test('周三 → 2', () {
      expect(weekTodayIndex(DateTime(2026, 9, 23)), 2);
    });
  });
}
