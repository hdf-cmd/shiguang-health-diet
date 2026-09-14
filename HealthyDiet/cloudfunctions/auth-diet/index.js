const cloud = require("@cloudbase/node-sdk");
const crypto = require("crypto");

const app = cloud.init({
  env: cloud.SYMBOL_CURRENT_ENV,
  credentials: require("./tcb_custom_login.json")
});
const auth = app.auth();
const db = app.database();

function hashPassword(password, salt) {
  return crypto.scryptSync(password, salt, 64).toString("hex");
}

exports.main = async (event) => {
  const isHttp = !!(event.httpMethod || event.headers);
  let body = event;
  if (typeof event.body === "string") {
    try {
      body = JSON.parse(event.body);
    } catch (e) {
      body = {};
    }
  } else if (body && typeof body.body === "object" && body.body !== null) {
    body = body.body;
  }

  const result = await handle(body);
  if (isHttp) {
    return {
      statusCode: 200,
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify(result)
    };
  }
  return result;
};

async function handle(body) {
  const action = body.action;
  const username = String(body.username || "").trim().toLowerCase();
  const password = String(body.password || "");

  if (!username || !password) {
    return { ok: false, message: "用户名或密码为空" };
  }
  if (!/^[a-zA-Z0-9_]{4,28}$/.test(username)) {
    return { ok: false, message: "用户名需为 4-28 位字母、数字或下划线" };
  }
  if (password.length < 8) {
    return { ok: false, message: "密码至少 8 位" };
  }

  const customUserId = "u_" + username;
  const users = db.collection("app_users");

  if (action === "register") {
    const exists = await users.where({ username }).count();
    if (exists.total > 0) {
      return { ok: false, message: "用户名已被占用" };
    }
    const salt = crypto.randomBytes(16).toString("hex");
    await users.add({
      username,
      customUserId,
      salt,
      pwdHash: hashPassword(password, salt),
      createdAt: Date.now()
    });
    return { ok: true };
  }

  if (action === "login") {
    const res = await users.where({ username }).limit(1).get();
    const user = res.data && res.data[0];
    if (!user || hashPassword(password, user.salt) !== user.pwdHash) {
      return { ok: false, message: "用户名或密码错误" };
    }
    const ticket = auth.createTicket(customUserId, {
      refresh: 3600 * 1000,
      expire: 30 * 24 * 3600 * 1000
    });
    return { ok: true, ticket };
  }

  return { ok: false, message: "未知操作" };
}
