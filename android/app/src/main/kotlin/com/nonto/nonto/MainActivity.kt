package com.nonto.nonto

import android.app.NotificationChannel
import android.app.NotificationManager
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    // Flutter 3.29+ 会默认把厂商离线通知点击 intent.data 当作 deep link 处理，
    // 厂商通道可能携带额外参数，自动解析会导致无匹配路由或白屏。
    override fun shouldHandleDeeplinking(): Boolean {
        return false
    }

    private val appSettingsChannel = "nonto/app_settings"
    private val aliyunPushConfigChannel = "nonto/aliyun_push_config"
    private val huaweiPushDiagnosticsChannel = "nonto/huawei_push_diagnostics"
    private val messageNotificationChannelId = "nonto_message_alerts"

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createMessageNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            appSettingsChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            aliyunPushConfigChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAliyunPushConfig" -> result.success(aliyunPushConfig())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            huaweiPushDiagnosticsChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getHuaweiPushDiagnostics" -> collectHuaweiPushDiagnostics(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun aliyunPushConfig(): Map<String, Any?> {
        return linkedMapOf(
            "androidAppKey" to BuildConfig.ALIYUN_PUSH_APP_KEY,
            "androidAppSecret" to BuildConfig.ALIYUN_PUSH_APP_SECRET,
            "huaweiAppIdConfigured" to BuildConfig.HUAWEI_PUSH_APP_ID.isNotBlank(),
            "oppoAppKeyConfigured" to BuildConfig.OPPO_PUSH_APP_KEY.isNotBlank(),
            "oppoAppSecretConfigured" to BuildConfig.OPPO_PUSH_APP_SECRET.isNotBlank(),
            "vivoAppIdConfigured" to BuildConfig.VIVO_PUSH_APP_ID.isNotBlank(),
            "vivoAppKeyConfigured" to BuildConfig.VIVO_PUSH_APP_KEY.isNotBlank(),
        )
    }

    private fun collectHuaweiPushDiagnostics(result: MethodChannel.Result) {
        thread {
            val diagnostics = collectAppAndNotificationDiagnostics().toMutableMap()
            diagnostics["huawei_app_id_configured"] =
                BuildConfig.HUAWEI_PUSH_APP_ID.isNotBlank()
            diagnostics.putAll(HuaweiPushDiagnosticsStore.snapshot(this))
            diagnostics.putAll(AliyunNativePushDiagnosticsStore.snapshot(this))
            runOnUiThread { result.success(diagnostics) }
        }
    }

    private fun collectAppAndNotificationDiagnostics(): Map<String, Any?> {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(
                    PackageManager.GET_SIGNING_CERTIFICATES.toLong()
                )
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_SIGNING_CERTIFICATES
            )
        }
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners.orEmpty()
        } else {
            @Suppress("DEPRECATION")
            info.signatures.orEmpty()
        }
        val signatureSha256 = signatures.firstOrNull()?.toByteArray()?.let { bytes ->
            MessageDigest.getInstance("SHA-256")
                .digest(bytes)
                .joinToString(":") { byte -> "%02X".format(byte) }
        }.orEmpty()
        val notificationManager = getSystemService(NotificationManager::class.java)
        val channelImportance = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager
                .getNotificationChannel(messageNotificationChannelId)
                ?.importance
        } else {
            null
        }
        val postNotificationsGranted =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED

        return linkedMapOf(
            "packageName" to packageName,
            "versionName" to info.versionName.orEmpty(),
            "versionCode" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode.toString()
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toString()
            },
            "signatureSha256" to signatureSha256,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "sdkInt" to Build.VERSION.SDK_INT,
            "notificationsEnabled" to
                NotificationManagerCompat.from(this).areNotificationsEnabled(),
            "postNotificationsGranted" to postNotificationsGranted,
            "notificationChannelId" to messageNotificationChannelId,
            "notificationChannelImportance" to channelImportance
        )
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun createMessageNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            messageNotificationChannelId,
            "南图消息提醒",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "南图消息与互动提醒"
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

}
