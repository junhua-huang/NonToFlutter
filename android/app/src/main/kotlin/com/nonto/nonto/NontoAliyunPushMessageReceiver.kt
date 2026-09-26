package com.nonto.nonto

import android.app.Notification
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import com.alibaba.sdk.android.push.MessageReceiver
import com.alibaba.sdk.android.push.notification.CPushMessage
import com.alibaba.sdk.android.push.notification.NotificationConfigure
import com.alibaba.sdk.android.push.notification.PushData
import com.aliyun.ams.push.AliyunPushPlugin

internal fun shouldDisplayAliyunPush(
    sdkWouldDisplay: Boolean,
    extractDedupeKey: () -> String?,
    claim: (String) -> Boolean
): Boolean {
    if (!sdkWouldDisplay) return false

    return try {
        val dedupeKey = extractDedupeKey() ?: return true
        claim(dedupeKey)
    } catch (_: Exception) {
        true
    }
}

class NontoAliyunPushMessageReceiver : MessageReceiver() {
    override fun hookNotificationBuild(): NotificationConfigure {
        return object : NotificationConfigure {
            override fun configBuilder(builder: Notification.Builder, pushData: PushData) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    builder.setChannelId("nonto_message_alerts")
                }
            }

            override fun configBuilder(builder: NotificationCompat.Builder, pushData: PushData) {
                builder.setChannelId("nonto_message_alerts")
                builder.setPriority(NotificationCompat.PRIORITY_HIGH)
            }

            override fun configNotification(notification: Notification, pushData: PushData) = Unit
        }
    }

    override fun showNotificationNow(context: Context, map: Map<String, String>): Boolean {
        val sdkWouldDisplay = super.showNotificationNow(context, map)
        val shouldDisplay = shouldDisplayAliyunPush(
            sdkWouldDisplay = sdkWouldDisplay,
            extractDedupeKey = { extractDedupeKey(context, map) },
            claim = { dedupeKey -> dedupeStore(context).claim(dedupeKey) }
        )
        AliyunNativePushDiagnosticsStore.recordDisplayDecision(
            context,
            if (shouldDisplay) "display" else "suppressed"
        )
        return shouldDisplay
    }

    private fun extractDedupeKey(context: Context, map: Map<String, String>): String? {
        val parsedExtraMap = PushData.parse(context, map)?.extraMap
        return mapValueAsString(parsedExtraMap, DEDUPE_KEY)
            ?: mapValueAsString(map, DEDUPE_KEY)
    }

    private fun mapValueAsString(map: Map<*, *>?, key: String): String? {
        return (map?.get(key) as? String)?.takeIf { it.isNotBlank() }
    }

    override fun onNotification(context: Context, title: String, summary: String, extraMap: Map<String, String>) {
        AliyunNativePushDiagnosticsStore.record(context, "onNotification")
        callFlutter("onNotification", mapOf("title" to title, "summary" to summary, "extraMap" to extraMap))
    }

    override fun onNotificationReceivedInApp(
        context: Context,
        title: String,
        summary: String,
        extraMap: Map<String, String>,
        openType: Int,
        openActivity: String,
        openUrl: String
    ) {
        AliyunNativePushDiagnosticsStore.record(
            context,
            "onNotificationReceivedInApp"
        )
        callFlutter(
            "onNotificationReceivedInApp",
            mapOf(
                "title" to title,
                "summary" to summary,
                "extraMap" to extraMap,
                "openType" to openType,
                "openActivity" to openActivity,
                "openUrl" to openUrl
            )
        )
    }

    override fun onMessage(context: Context, cPushMessage: CPushMessage) {
        AliyunNativePushDiagnosticsStore.record(context, "onMessage")
        callFlutter(
            "onMessage",
            mapOf(
                "title" to cPushMessage.title,
                "content" to cPushMessage.content,
                "msgId" to cPushMessage.messageId,
                "appId" to cPushMessage.appId,
                "traceInfo" to cPushMessage.traceInfo
            )
        )
    }

    override fun onNotificationOpened(context: Context, title: String, summary: String, extraMap: String) {
        AliyunNativePushDiagnosticsStore.record(context, "onNotificationOpened")
        callFlutter("onNotificationOpened", mapOf("title" to title, "summary" to summary, "extraMap" to extraMap))
    }

    override fun onNotificationRemoved(context: Context, messageId: String) {
        AliyunNativePushDiagnosticsStore.record(context, "onNotificationRemoved")
        callFlutter("onNotificationRemoved", mapOf("msgId" to messageId))
    }

    override fun onNotificationClickedWithNoAction(context: Context, title: String, summary: String, extraMap: String) {
        AliyunNativePushDiagnosticsStore.record(
            context,
            "onNotificationClickedWithNoAction"
        )
        callFlutter(
            "onNotificationClickedWithNoAction",
            mapOf("title" to title, "summary" to summary, "extraMap" to extraMap)
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun callFlutter(method: String, arguments: Map<String, Any?>) {
        try {
            AliyunPushPlugin.sInstance.callFlutterMethod(method, arguments as Map<String, Any>)
        } catch (e: Exception) {
            // The Flutter engine can be absent for killed-state vendor callbacks.
        }
    }

    private companion object {
        const val DEDUPE_KEY = "dedupe_key"

        @Volatile
        var pushDedupeStore: AliyunPushDedupeStore? = null

        fun dedupeStore(context: Context): AliyunPushDedupeStore {
            return pushDedupeStore ?: synchronized(this) {
                pushDedupeStore ?: createAliyunPushDedupeStore(context.applicationContext).also {
                    pushDedupeStore = it
                }
            }
        }
    }
}
