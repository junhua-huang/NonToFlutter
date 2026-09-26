import java.util.Properties
import java.io.File
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
val releaseStoreFilePath = keystoreProperties.getProperty("storeFile", "")
val releaseStoreFile = if (releaseStoreFilePath.isBlank()) {
    null
} else if (File(releaseStoreFilePath).isAbsolute) {
    File(releaseStoreFilePath)
} else {
    keystorePropertiesFile.parentFile.resolve(releaseStoreFilePath)
}

val localPropertiesFile = rootProject.file("local.properties")
val localProperties = Properties()
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

fun aliyunPushProperty(name: String): String =
    localProperties.getProperty(name)?.trim().orEmpty()

fun quotedBuildConfigValue(value: String): String =
    "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""

val aliyunPushAppKey = aliyunPushProperty("aliyun.push.appKey")
val aliyunPushAppSecret = aliyunPushProperty("aliyun.push.appSecret")
val huaweiPushAppId = aliyunPushProperty("huawei.push.appId")
val oppoPushAppKey = aliyunPushProperty("oppo.push.appKey")
val oppoPushAppSecret = aliyunPushProperty("oppo.push.appSecret")
val vivoPushAppId = aliyunPushProperty("vivo.push.appId")
val vivoPushAppKey = aliyunPushProperty("vivo.push.appKey")

android {
    namespace = "com.nonto.nonto"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
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
        manifestPlaceholders += mapOf(
            "ALIYUN_PUSH_APP_KEY" to aliyunPushAppKey,
            "ALIYUN_PUSH_APP_SECRET" to aliyunPushAppSecret,
            "HUAWEI_PUSH_APP_ID" to if (huaweiPushAppId.isBlank()) "" else "appid=$huaweiPushAppId",
            "OPPO_PUSH_APP_KEY" to oppoPushAppKey,
            "OPPO_PUSH_APP_SECRET" to oppoPushAppSecret,
            "VIVO_PUSH_APP_ID" to vivoPushAppId,
            "VIVO_PUSH_APP_KEY" to vivoPushAppKey,
        )
        buildConfigField("String", "ALIYUN_PUSH_APP_KEY", quotedBuildConfigValue(aliyunPushAppKey))
        buildConfigField("String", "ALIYUN_PUSH_APP_SECRET", quotedBuildConfigValue(aliyunPushAppSecret))
        buildConfigField("String", "HUAWEI_PUSH_APP_ID", quotedBuildConfigValue(huaweiPushAppId))
        buildConfigField("String", "OPPO_PUSH_APP_KEY", quotedBuildConfigValue(oppoPushAppKey))
        buildConfigField("String", "OPPO_PUSH_APP_SECRET", quotedBuildConfigValue(oppoPushAppSecret))
        buildConfigField("String", "VIVO_PUSH_APP_ID", quotedBuildConfigValue(vivoPushAppId))
        buildConfigField("String", "VIVO_PUSH_APP_KEY", quotedBuildConfigValue(vivoPushAppKey))
    }

    signingConfigs {
        if (keystorePropertiesFile.exists() && releaseStoreFile?.exists() == true) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias", "")
                keyPassword = keystoreProperties.getProperty("keyPassword", "")
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword", "")
            }
        }
    }

    buildTypes {
        release {
            // 厂商通道会校验包名 + 签名证书；有 release keystore 时必须使用正式签名。
            // 没有 key.properties 的本地开发环境降级 debug，但该 APK 不能用于厂商通道验收。
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            // 暂时禁用代码压缩和混淆以排查问题
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
}
