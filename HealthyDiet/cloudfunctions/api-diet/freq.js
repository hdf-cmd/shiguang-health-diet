/* 食物频次聚合（M12-③）：与数据库无关的纯逻辑，node --test 可直接覆盖。
 * index.js 的 /diet/records/freq 路由只负责把 fetchPage 接到真实查询上。 */

function countNames(records) {
  const counts = {};
  for (const r of records || []) {
    const name = r && typeof r.name === 'string' ? r.name.trim() : '';
    if (!name) continue;
    counts[name] = (counts[name] || 0) + 1;
  }
  return counts;
}

/* 翻页收集直到短页；maxPages 截断时 complete=false 自报，不静默少算。
 * pageSize 默认 1000 与 index.js 既有的单次上限同量级（/report/month）。 */
async function collectAll(fetchPage, { pageSize = 1000, maxPages = 20 } = {}) {
  const records = [];
  for (let page = 0; page < maxPages; page++) {
    const rows = await fetchPage(page * pageSize, pageSize);
    records.push(...rows);
    if (rows.length < pageSize) return { records, complete: true };
  }
  return { records, complete: false };
}

module.exports = { countNames, collectAll };
