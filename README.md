# 南图 · iOS 原生版

[![Native iOS](https://github.com/junhua-huang/NonToFlutter/actions/workflows/native-ios.yml/badge.svg?branch=ios)](https://github.com/junhua-huang/NonToFlutter/actions/workflows/native-ios.yml)

`ios` 分支使用 Swift + SwiftUI 构建南图 iPhone / iPad 客户端，连接原有后端。

- 保留品牌蓝 **#1D9BF0** 和原 N 图标。
- 使用 **iOS 26 Liquid Glass**、原生导航、标签栏、表单和系统交互。
- 直接使用 URLSession、Keychain、UserNotifications、SF Symbols、PhotosPicker、AVPlayer 和系统存储。
- 原生工程不依赖 Flutter、CocoaPods 或第三方 Swift 包。

打开 `ios/Nonto.xcodeproj`，选择 `Nonto` scheme。需要 Xcode 26+ 和 iOS / iPadOS 26+。Windows 用户可通过仓库的 **Native iOS** GitHub Actions 检查编译和测试；TestFlight 还需要配置苹果签名。

[原生版功能、构建和待验证事项](ios/README.md)

Flutter 代码继续保留作为其他平台实现和接口参考；其原始开发分支是 `master`。
