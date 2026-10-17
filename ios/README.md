# 南图 · 原生 iOS

分支 `ios` 从 `master` 的 `c24b5a3` 创建。`ios/Nonto.xcodeproj` 是独立的 SwiftUI 应用；无需安装 Flutter、CocoaPods 或第三方包。原 Flutter 代码保留用于其他平台及核对接口。

## 设计和系统能力

- iOS / iPadOS 26 起，Xcode 26 或更高版本。
- 保留原品牌蓝 `#1D9BF0`、点赞粉 `#F91880` 和现有 N 图标。
- 原生 `TabView`、`NavigationStack`、工具栏、表单、菜单和系统弹窗采用 Liquid Glass；操作按钮使用 `.glass` / `.glassProminent`，悬浮输入栏使用 `.glassEffect`。内容层保持可读，遵从系统的浅深色、动态字体和降低透明度设置。
- 网络：`URLSession` 和 `URLSessionWebSocketTask`。
- 凭据：Keychain，解锁后可访问且不随设备迁移。
- 存储：系统 Caches 目录中的账号独立 JSON 快照、UserDefaults 偏好/文字草稿/待发送记录。缓存带文件保护；与 Flutter 的数据库独立，已有服务端数据直接读取。
- 图标：SF Symbols；媒体：PhotosPicker、AVPlayer、系统分享面板。
- 通知：UserNotifications 原生授权、前台提醒、测试通知和角标；后台远程通知的 APNs 服务端通道仍待接入，不能通过后台保持 WebSocket 替代。

## 当前实现

| 模块 | 原生功能 |
| --- | --- |
| 账号 | 邮箱密码登录、注册、邮箱验证码、密码找回、登录续期、退出、账号注销 |
| 动态 | 推荐/最新/相关分页流、详情、浏览计数、点赞、评论及回复、删除、编辑、引用、会话内分享 |
| 发布 | 文字、最多 9 张照片或单段视频、JPEG 处理、COS 预签名上传和服务端确认、可见范围、认证身份、文字草稿 |
| 私聊 / 群聊 | 会话列表、历史分页、已读、文本/图片/视频、社区消息引用/撤回、消息失败重试、账号独立的持久待发送记录 |
| 实时 | 原协议 v1 的 auth / sync / ack_receive / ping、重连和前后台断连；HTTP 校准历史，使用现有幂等请求编号发送 |
| 发现 | 用户/动态/话题搜索、服务器搜索记录、热门/关注话题 |
| 通知列表 | 未读角标、全部已读、删除、关联动态/评论/社群跳转 |
| 好友/资料 | 好友申请接受拒绝、添加/取消申请/删除好友、公开资料、编辑名称介绍头像封面、屏蔽举报 |
| 社群 | 发现/我的、创建编辑、加入审核、成员、群聊、社群动态、公告、管理员/移出/封禁、解散 |
| 身份 | 认证申请、材料上传、作品链接、申请记录和审核结果 |
| 漫展 | 城市筛选、活动列表详情、关注、我的活动、创建编辑、图片上传、一级评论 |
| 设置 | 主题、隐私和发帖默认范围、提醒偏好、密码、屏蔽列表、缓存、协议 |

本版的目标是用系统能力覆盖核心使用路径，不复制跨平台兼容层。Windows 安装、Android/鸿蒙推送、Web 部署控制台、第三方图标/播放器插件不属于原生 iPhone 客户端。

仍需后续专门验证或补充：APNs 后台/杀进程推送、真实账号的后端联调、真机与辅助功能视觉验收；细节包括私聊引用/撤回、完整漫展评论互动、精细图片裁剪、社群 @ 输入建议、视频压缩/封面生成和消息附件文件选择。现有法律文本从 Flutter 提取，包含原项目的示例联系地址，上架前应由项目维护者核实；本次没有自行改写法律承诺。

## 构建检查（Windows 无需 Xcode）

推送 `ios` 会自动运行 `.github/workflows/native-ios.yml`：

1. 校验工程生成结果。
2. 在 macOS 上编译原生应用并运行 XCTest。
3. 额外编译 iPhone Release 目标（不签名）。
4. 上传日志、测试结果和模拟器应用，保留 7 天。

模拟器 `.app` 不能安装到 iPhone；这个流程也不会自动上传 TestFlight。

有 Mac 时可直接打开 `ios/Nonto.xcodeproj`，选择 Nonto scheme 和模拟器。命令行示例：

```sh
python3 ios/scripts/generate_project.py
xcodebuild -project ios/Nonto.xcodeproj -scheme Nonto \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO test
```

实际模拟器名称以 `xcrun simctl list devices available` 为准。工程文件已提交，Python 脚本仅在增删 Swift 源码/资源后重跑；无额外 Python 依赖。

## 真机 / TestFlight

初始 Bundle ID 为 `online.nonto.native`。维护者应在苹果开发者账户中确认相应 App ID、App Store Connect 应用、Development Team 和签名描述文件，或先修改工程生成脚本中的 Bundle ID 再重新生成。需要云端签名上传时再配置该仓库的证书及 App Store Connect 凭据；不将这些凭据提交到代码。

## 后端契约

默认仍连接 `https://www.nonto.online/api` 与 `wss://www.nonto.online/ws`。可在 `APIClient` 初始化时注入其他地址以开发和测试。生产请求保持源项目 `access_token` 查询参数契约；令牌仅附加到自己的 API，COS 请求不携带应用凭据。跨域重定向被拒绝，401 只共享一次续期，并保留原始分页/筛选参数；账号变化后丢弃旧会话响应。

测试使用 URLProtocol 假服务器，不调用生产 API，也不创建、修改或删除真实账号/社群/动态。
