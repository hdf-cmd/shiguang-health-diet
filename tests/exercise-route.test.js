// tests/exercise-route.test.js
// 运动记录幂等：uid+externalId 查重、非法 externalId 忽略、热量校验。
import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { addExercise, listExistingKeys, normalizeExternalId } = require(
  "../HealthyDiet/cloudfunctions/api-diet/services/exercise_route"
);

function makeDb(seed = []) {
  const rows = seed.map((r, i) => ({ _id: `seed${i}`, ...r }));
  return {
    rows,
    command: { in: (arr) => ({ __in: arr }) },
    collection(name) {
      assert.equal(name, "sg_exercises");
      return {
        where(query) {
          return {
            limit() {
              return {
                async get() {
                  return {
                    data: rows.filter((r) =>
                      Object.entries(query).every(([k, v]) =>
                        v && typeof v === "object" && "__in" in v
                          ? v.__in.includes(r[k])
                          : r[k] === v
                      )
                    ),
                  };
                },
              };
            },
          };
        },
        async add(doc) {
          const _id = `id${rows.length + 1}`;
          rows.push({ _id, ...doc });
          return { id: _id };
        },
      };
    },
  };
}

const base = { date: "2026-11-18", key: "run", name: "跑步", emoji: "🏃", amount: 1.18, unit: "km", kcal: 66 };

test("无 externalId：正常插入且不写字段", async () => {
  const db = makeDb();
  const res = await addExercise(db, "u1", base, "2026-11-18");
  assert.equal(res.ok, true);
  assert.equal(db.rows.length, 1);
  assert.equal("externalId" in db.rows[0], false);
});

test("带 externalId：首次入库并保存", async () => {
  const db = makeDb();
  const res = await addExercise(db, "u1", { ...base, externalId: "mi:a" }, "2026-11-18");
  assert.equal(res.ok, true);
  assert.equal(db.rows[0].externalId, "mi:a");
});

test("同 uid+externalId 重复提交：返回已有行、不新增", async () => {
  const db = makeDb();
  await addExercise(db, "u1", { ...base, externalId: "mi:a" }, "2026-11-18");
  const res = await addExercise(db, "u1", { ...base, externalId: "mi:a" }, "2026-11-18");
  assert.equal(res.ok, true);
  assert.equal(res.duplicate, true);
  assert.equal(db.rows.length, 1);
  assert.equal(res.id, db.rows[0]._id);
});

test("不同 uid 同 externalId：各自入库", async () => {
  const db = makeDb();
  await addExercise(db, "u1", { ...base, externalId: "mi:a" }, "2026-11-18");
  await addExercise(db, "u2", { ...base, externalId: "mi:a" }, "2026-11-18");
  assert.equal(db.rows.length, 2);
});

test("热量为 0：拒绝", async () => {
  const db = makeDb();
  const res = await addExercise(db, "u1", { ...base, kcal: 0 }, "2026-11-18");
  assert.equal(res.ok, false);
  assert.equal(db.rows.length, 0);
});

test("非法 externalId（超长/非字符串/空白）被忽略", async () => {
  const db = makeDb();
  await addExercise(db, "u1", { ...base, externalId: "x".repeat(81) }, "2026-11-18");
  await addExercise(db, "u1", { ...base, externalId: 123 }, "2026-11-18");
  await addExercise(db, "u1", { ...base, externalId: "   " }, "2026-11-18");
  assert.equal(db.rows.length, 3);
  assert.equal(db.rows.every((r) => !("externalId" in r)), true);
});

test("normalizeExternalId：trim 与长度上限", () => {
  assert.equal(normalizeExternalId("  mi:a  "), "mi:a");
  assert.equal(normalizeExternalId(""), "");
  assert.equal(normalizeExternalId(null), "");
  assert.equal(normalizeExternalId("x".repeat(80)), "x".repeat(80));
  assert.equal(normalizeExternalId("x".repeat(81)), "");
});


test("listExistingKeys：窗口内 externalId + 内容签名（含老数据）", async () => {
  const db = makeDb([
    { uid: "u1", date: "2026-11-18", key: "run", amount: 1.18, kcal: 66, externalId: "mi:a" },
    { uid: "u1", date: "2026-11-18", key: "run", amount: 1.18, kcal: 66 },
    { uid: "u1", date: "2026-11-01", key: "run", amount: 9, kcal: 500 },
    { uid: "u2", date: "2026-11-18", key: "run", amount: 1.18, kcal: 66 },
  ]);
  const res = await listExistingKeys(db, "u1", ["2026-11-18", "bad-date"]);
  assert.deepEqual(res.externalIds, ["mi:a"]);
  assert.deepEqual(res.signatures, [
    "2026-11-18|run|1.18|66",
    "2026-11-18|run|1.18|66",
  ]);
});
