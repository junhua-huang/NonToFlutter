/**
 * video_player_ohos - Android 端（委托给 video_player）
 *
 * 本插件的 Android 实现委托给官方 video_player 包，
 * 故 Android 端无需额外原生代码。MethodChannel 由 video_player 自行注册。
 */
package com.nonto.video_player_ohos

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin

class VideoPlayerOhosPlugin : FlutterPlugin {
    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        // Android 端委托给 video_player 插件处理，无需额外注册
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {}
}