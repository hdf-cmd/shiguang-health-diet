import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

/* ---------- 版本号单一来源 ----------
 * versionName/versionCode 都从仓库根目录 package.json 的 version 推导，
 * 避免手改多处漂移；versionCode 用 major*10000+minor*100+patch 保证单调递增。 */
val repoRoot = rootProject.projectDir.parentFile
val appVersion: String = Regex("\"version\"\\s*:\\s*\"([^\"]+)\"")
    .find(File(repoRoot, "package.json").readText())
    ?.groupValues?.get(1) ?: "0.0.0"
val appVersionCode: Int = appVersion.split(".").let { p ->
    p.getOrElse(0) { "0" }.toIntOrNull()!! * 10000 +
        p.getOrElse(1) { "0" }.toIntOrNull()!! * 100 +
        p.getOrElse(2) { "0" }.toIntOrNull()!!
}

/* ---------- release 签名 ----------
 * 凭据放本地 keystore.properties（已入 .gitignore，严禁入库）。
 * 文件缺失时不签名，保证他人 clone 后仍能构建未签名包。 */
val keystorePropsFile = rootProject.file("keystore.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) keystorePropsFile.inputStream().use { load(it) }
}

android {
    namespace = "com.healthydiet.app"
    /* 36：部分厂商只在应用声明适配 Android 16 时才放开「胶囊/焦点通知」这类新形态通知 */
    compileSdk = 36

    defaultConfig {
        applicationId = "com.healthydiet.app"
        minSdk = 26
        targetSdk = 36
        versionCode = appVersionCode
        versionName = appVersion
    }

    signingConfigs {
        create("release") {
            if (keystorePropsFile.exists()) {
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (keystorePropsFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
    lint {
        // release 构建不跑 lintVital：该步骤会访问 dl.google.com 查询依赖元数据，
        // 本机到 Google 不可达（SYN 重试挂起，构建表现为零进展卡死）。
        // 需要 Android Lint 时手动执行：gradlew.bat lintDebug
        checkReleaseBuilds = false
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        buildConfig = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("org.nanohttpd:nanohttpd:2.3.1")
}

/* ---------- 反馈3：web 资源单一事实来源 ----------
 * 构建前把仓库根目录的 index.html/css/js 同步进 assets/web，
 * 避免“根目录改了、assets 忘改”的双份漂移。无 node 环境时忽略失败（assets 提交副本兜底）。 */
tasks.register<Exec>("syncWebAssets") {
    workingDir = rootProject.projectDir.parentFile   // 仓库根（HealthyDiet 的上一级）
    commandLine("node", "scripts/sync-web-assets.mjs")
    isIgnoreExitValue = true
}
tasks.named("preBuild") { dependsOn("syncWebAssets") }