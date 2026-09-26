package com.nonto.nonto

import com.huawei.hms.push.HmsMessageService
import com.huawei.hms.push.RemoteMessage

class HuaweiPushDiagnosticsService : HmsMessageService() {
    override fun onNewToken(token: String?) {
        super.onNewToken(token)
        HuaweiPushDiagnosticsStore.record(this, "onNewToken")
    }

    override fun onMessageReceived(message: RemoteMessage?) {
        super.onMessageReceived(message)
        HuaweiPushDiagnosticsStore.record(this, "onMessageReceived")
    }

    override fun onMessageSent(messageId: String?) {
        super.onMessageSent(messageId)
        HuaweiPushDiagnosticsStore.record(this, "onMessageSent")
    }

    override fun onSendError(messageId: String?, exception: Exception?) {
        super.onSendError(messageId, exception)
        HuaweiPushDiagnosticsStore.record(this, "onSendError")
    }

    override fun onDeletedMessages() {
        super.onDeletedMessages()
        HuaweiPushDiagnosticsStore.record(this, "onDeletedMessages")
    }
}
