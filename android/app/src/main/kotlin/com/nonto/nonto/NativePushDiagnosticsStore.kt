package com.nonto.nonto

import android.content.Context

private const val PREFS = "nonto_native_push_diagnostics"

object HuaweiPushDiagnosticsStore {
    fun record(context: Context, event: String) {
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("huawei_vendor_last_event", event)
            .putString("huawei_vendor_last_event_at", System.currentTimeMillis().toString())
            .apply()
    }

    fun snapshot(context: Context): Map<String, Any?> {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return linkedMapOf(
            "huawei_vendor_last_event" to prefs.getString("huawei_vendor_last_event", ""),
            "huawei_vendor_last_event_at" to prefs.getString("huawei_vendor_last_event_at", "")
        )
    }
}

object AliyunNativePushDiagnosticsStore {
    fun record(context: Context, callback: String) {
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("aliyun_native_last_callback", callback)
            .putString("aliyun_native_last_callback_at", System.currentTimeMillis().toString())
            .apply()
    }

    fun recordDisplayDecision(context: Context, decision: String) {
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("aliyun_native_last_display_decision", decision)
            .putString(
                "aliyun_native_last_display_decision_at",
                System.currentTimeMillis().toString()
            )
            .apply()
    }

    fun snapshot(context: Context): Map<String, Any?> {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return linkedMapOf(
            "aliyun_native_last_callback" to prefs.getString("aliyun_native_last_callback", ""),
            "aliyun_native_last_callback_at" to prefs.getString("aliyun_native_last_callback_at", ""),
            "aliyun_native_last_display_decision" to
                prefs.getString("aliyun_native_last_display_decision", ""),
            "aliyun_native_last_display_decision_at" to
                prefs.getString("aliyun_native_last_display_decision_at", "")
        )
    }
}
