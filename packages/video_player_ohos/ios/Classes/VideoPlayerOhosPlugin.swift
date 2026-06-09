//
//  video_player_ohos - iOS 端（委托给 video_player）
//
//  本插件的 iOS 实现委托给官方 video_player / video_player_avfoundation 包，
//  故 iOS 端无需额外原生代码。
//

import Flutter
import UIKit

public class VideoPlayerOhosPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        // iOS 端委托给 video_player_avfoundation 插件处理，无需额外注册
    }
}