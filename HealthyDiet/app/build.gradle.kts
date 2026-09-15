plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.healthydiet.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.healthydiet.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
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
