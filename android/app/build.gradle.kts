import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 加载密钥库配置
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val huaweiAppId = providers.gradleProperty("HUAWEI_APPID")
    .orElse(providers.environmentVariable("HUAWEI_APPID"))
    .orElse("")
    .get()

android {
    namespace = "com.nonto.nonto"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nonto.nonto"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ── 极光推送 manifestPlaceholders ──
        // JPUSH_APPKEY: 极光应用 AppKey；JPUSH_CHANNEL: 渠道名（统计用）
        // 厂商通道证书在极光控制台配置；华为通道还需要把 HMS AppID 注入 Manifest。
        // 本地/CI 可通过 Gradle 属性或环境变量 HUAWEI_APPID 传入（常见格式：appid=123456）。
        manifestPlaceholders["JPUSH_APPKEY"] = "c9c5db77d7cb1a466951e774"
        manifestPlaceholders["JPUSH_CHANNEL"] = "nonto-default"
        manifestPlaceholders["HUAWEI_APPID"] = huaweiAppId
        manifestPlaceholders["XIAOMI_APPID"] = ""
        manifestPlaceholders["XIAOMI_APPKEY"] = ""
        manifestPlaceholders["OPPO_APPKEY"] = ""
        manifestPlaceholders["OPPO_APPID"] = ""
        manifestPlaceholders["OPPO_APPSECRET"] = ""
        manifestPlaceholders["VIVO_APPKEY"] = ""
        manifestPlaceholders["VIVO_APPID"] = ""
        manifestPlaceholders["MEIZU_APPID"] = ""
        manifestPlaceholders["MEIZU_APPKEY"] = ""
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias", "")
                keyPassword = keystoreProperties.getProperty("keyPassword", "")
                storeFile = file(keystoreProperties.getProperty("storeFile", ""))
                storePassword = keystoreProperties.getProperty("storePassword", "")
            }
        }
    }

    buildTypes {
        release {
            // 先使用调试签名测试构建是否正常
            signingConfig = signingConfigs.getByName("debug")
            // 暂时禁用代码压缩和混淆以排查问题
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
