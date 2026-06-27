package com.nonto.nonto

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Flutter 3.29+ 会默认把厂商离线通知点击 intent.data 当作 deep link 处理，
    // 极光厂商通道可能携带 n_extra 等参数，自动解析会导致无匹配路由或白屏。
    override fun shouldHandleDeeplinking(): Boolean {
        return false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createJPushNotificationChannel()
    }

    private fun createJPushNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            "nonto_message",
            "南图消息通知",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "南图消息与互动通知"
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }
}
