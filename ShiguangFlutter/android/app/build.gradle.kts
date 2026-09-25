import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.healthydiet.shiguang_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // M4-T6：flutter_local_notifications 10+ 起强制要求 core library
        // desugaring（调度通知用 java.time，向下兼容旧机型）。配置照插件
        // README「Gradle setup」Kotlin DSL 段（22.3.1 安装源 :250-262）。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        multiDexEnabled = true // 同上：desugaring 前提之一（README :252-254）
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.healthydiet.shiguang_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // M5-T1：release 签名读 android/key.properties（该文件与 *.jks 均 git-ignore）。
    // 缺失时回退 debug 签名——他人 clone/CI 无密钥也能 assembleRelease（非交付包）。
    val keystoreProperties = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null
        && rootProject.file(keystoreProperties.getProperty("storeFile")).exists()

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                // storeFile 以 android/（rootProject）为基准，与 Step1 生成 key.properties 的相对路径一致。
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug") // 回退语义见上
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // M4-T6：插件 README 指定版本（flutter_local_notifications 22.3.1）
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
