/* 版本号：唯一来源是仓库根目录 package.json 的 version。
 * 此处必须与之一致 —— CI 会跑 scripts/check-version.mjs 校验，不一致直接失败。
 * Android 侧的 versionName/versionCode 由 app/build.gradle.kts 从 package.json 自动读取，无需手改。 */
export const APP_VERSION = '1.1.0';