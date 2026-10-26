# 原生 APNs 接入与验收

客户端代码位于 `ios` 分支；配套服务端位于 [NonToPython/ios](https://github.com/junhua-huang/NonToPython/tree/ios)，部署说明见该仓库的 `docs/APNS.md`。当前改动没有部署生产服务或签名上传 TestFlight。

## 苹果开发者后台

1. 在 Certificates, Identifiers & Profiles → Identifiers 中确认 App ID 的 Bundle ID 为 `online.nonto.native`，开启 Push Notifications。
2. 在 Keys 创建有 Apple Push Notifications service 权限的密钥，保存 `.p8`、Key ID 和 Team ID。按所创建密钥的范围选择对应 App ID 和环境。私钥只配置到服务器。
3. 为该 App ID 重新生成或自动更新开发/分发描述文件；在 Xcode 设置自己的 Development Team，或在现有签名流水线使用更新后的描述文件。
4. 本工程已有 `aps-environment` entitlement。Debug 默认 `development`；Release 默认 `production`，用于 TestFlight/App Store。使用开发签名运行 Release 时，须同时覆盖 `APNS_ENVIRONMENT=development`，与实际签名环境一致。该值同时写入 Info.plist 并上传给服务端。

## 客户端链路

- 首次启动及回到前台时检查系统授权；用户在“我的 → 设置 → 消息提醒”允许通知并开启“系统推送”，保存后注册 APNs。
- 每次运行从系统获取 APNs token，不缓存 token。安装 ID 与撤销凭据保存在 Keychain；服务端存 token，账号变化或关闭推送时串行解绑。
- `/push/devices/register` 必须返回 `apns_supported=true` 与对应账号、环境的确认；旧服务端的普通成功响应不会显示为推送已连接。
- 服务端尚未配置凭据时显示“设备已绑定，等待服务器启用推送”。
- 前台 WebSocket 本地提醒与 APNs 使用相同的 `message:<id>` / `notification:<id>` 去重键；当前聊天不弹新消息提醒。
- 冷启动通知点击等待登录恢复，校验 recipient_id 后打开目标；其他账号的通知不会打开其内容。完整通知详情仍由鉴权 API 获取。
- 普通提醒由系统显示，后台不维持 WebSocket，不使用不可靠的静默推送代替可见提醒。

## 真机验收

### 举报收件回执

配套后端生成 `report_received` 系统通知，举报与回执在同一事务提交。客户端收到已提交的 `notification` 响应后立即刷新通知列表，前台 HTTP 回执、WebSocket 与 APNs 共享通知 ID 去重。系统提醒仅展示「举报已收到」和固定说明，不展示举报理由；点击通知后可查看自己的举报处理记录。关闭系统推送不会移除应用内回执。该功能需先部署后端 `docs/REPORT_RECEIPTS.md` 所述改动。

1. 先部署后端、执行数据库迁移、配置 APNs 密钥，再安装包含推送能力的签名应用。未签名模拟器构建只能验证编译和状态逻辑。
2. 登录，在消息提醒页面允许系统通知并开启“系统推送”，确认设备状态。点击“发送远程测试通知”验证服务器 → APNs → 设备；每个账号测试间隔 60 秒。“本地测试通知”仅验证系统授权，不能证明 APNs 通道已接通。
3. 用另一账号发送私信：分别验证前台当前会话、前台其他页面、退到桌面、锁屏和系统终止后的提醒；验证点击后进入正确会话，冷启动也能打开。
4. 验证关闭消息提醒、关闭全部推送、关闭声音、屏蔽关系、同一消息只提醒一次。
5. 验证退出、换账号、断网退出后恢复网络、令牌轮换；确认设备绑定按当前账号更新，并且旧通知不能越过账号/内容权限检查。
6. 分别验证开发签名的 sandbox token 和 TestFlight 的 production token。不要将两种环境的 token 互换使用。

参考：[注册 APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)、[提供方连接](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns)、[发送请求](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)。
