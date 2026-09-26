# Android 厂商推送通道修复设计

日期：2026-06-27

## 背景

用户反馈：当前厂商通道仍然有问题，多种品牌手机在 App 后台时看不到系统推送通知；只有进入前台再返回后台后，App 图标右上角未读数才增加。

现有证据显示，未读数同步链路基本可用，但后台系统通知链路不可靠：

- Flutter 端使用 `jpush_flutter: ^3.0.2`，本地解析到的插件版本为 `3.4.6`。
- `jpush_flutter-3.4.6/android/build.gradle` 仅依赖 `cn.jiguang.sdk:jpush:6.1.0`，未内置华为/小米/OPPO/vivo/魅族厂商通道插件。
- App 工程 `android/app/build.gradle.kts` 中厂商占位大多为空，只有 `HUAWEI_APPID` 可从 Gradle property / 环境变量读取。
- App 工程 release 构建当前固定使用 debug 签名；厂商通道通常校验包名 + 签名证书 + 控制台配置，debug 签名会导致厂商通道注册或投递失败。
- 后端已通过 JPush REST API 发送 Android notification payload，并支持 `options.third_party_channel`，但运行时失败原因需要更清晰的日志暴露。

## 目标

1. 让 release APK 具备真正使用厂商离线通道的基础能力。
2. 确保 release 构建优先使用正式签名，避免厂商控制台证书校验不匹配。
3. 让厂商 AppID/AppKey/AppSecret 可通过构建配置注入，不把敏感配置硬编码进源码。
4. 保留并强化后端 JPush 第三方通道 payload 和失败日志，便于定位极光/厂商侧错误。
5. 增加回归测试，避免以后又退回“只有基础 JPush，无厂商插件/真签名”的状态。

## 非目标

- 不在源码中提交真实厂商 AppSecret 或私密证书。
- 不重写通知中心、聊天未读数、WebSocket 同步架构。
- 不承诺在没有厂商控制台配置、真机权限、后台权限、电池策略允许的情况下 100% 到达。
- 不新增可视化验证流程；本轮以构建、日志和可检查配置为主。

## 推荐方案

采用“厂商插件 + release 真签名 + 可诊断日志/测试”组合修复。

仅修签名会留下“APK 没有厂商通道 SDK”的问题；仅加厂商插件会留下“厂商证书与 APK 签名不匹配”的问题。多品牌都失败说明这是系统性链路问题，应同时补齐设备侧 SDK 能力、构建签名和服务端诊断。

## 前端 Android 设计

### 1. 厂商配置读取

在 `android/app/build.gradle.kts` 中引入通用读取函数，从 Gradle property 或环境变量读取厂商配置：

- `HUAWEI_APPID`
- `XIAOMI_APPID`
- `XIAOMI_APPKEY`
- `OPPO_APPID`
- `OPPO_APPKEY`
- `OPPO_APPSECRET`
- `VIVO_APPID`
- `VIVO_APPKEY`
- `MEIZU_APPID`
- `MEIZU_APPKEY`

Manifest placeholders 继续使用这些键，但不再把非华为厂商固定为空字符串。没有传入时仍为空，保证本地构建不因缺少私密配置失败。

### 2. 厂商通道依赖

在 Android app 模块加入极光厂商通道插件依赖，覆盖当前后端声明支持的通道：华为、小米、OPPO、vivo、魅族。

依赖版本应与当前 JPush Android SDK `6.1.0` 兼容。若构建仓库无法解析某个厂商插件版本，应停止并按构建错误调整到极光官方可解析版本，不能用不可验证的版本继续提交。

### 3. release 签名

`release` buildType 改为：

- 如果 `key.properties` 存在并创建了 `signingConfigs.release`，则使用 release 签名。
- 如果不存在 release 签名配置，本地开发可降级 debug 签名，但必须打印/保留明确注释，说明该包不能用于厂商通道验证。

当前仓库已有 `android/key.properties` 和 `nonto-release-key.jks`，因此正常 release 构建应使用正式签名。

### 4. Flutter deep link 处理

`MainActivity` 重写 `shouldHandleDeeplinking(): Boolean = false`。

JPush 插件 README 明确提示 Flutter 3.29+ 点击厂商离线通知可能被 Flutter 自动 deep link 处理误解析，导致白屏。禁用 Flutter 自动 deep link 不影响当前应用内手写的通知点击跳转，因为跳转由 `PushService.onOpenNotification` 解析 extras 后执行。

### 5. 客户端诊断

保留现有 `PushService` 的 JPush setup、registrationId 上报、前后台状态上报逻辑。必要时增加非敏感 debug 日志，输出：

- registrationId 是否为空；
- `/push/register` 是否成功；
- `/push/device-state` 是否成功；
- 当前上报的 app_state。

不打印 JWT、厂商 secret 或其它敏感信息。

## 后端设计

### 1. Payload 保持 notification 类型

继续使用 JPush REST API 的 Android `notification.android` payload，而不是改为 custom message。厂商后台通知栏依赖 notification 类型；custom message 在后台通常不会自动出通知栏。

### 2. third_party_channel 保持配置化

保留：

- `JPUSH_ENABLE_THIRD_PARTY_CHANNEL`
- `JPUSH_THIRD_PARTY_CHANNELS`

默认支持 `huawei,xiaomi,oppo,vivo,meizu`。

后端只声明期望走第三方通道；真正能否走通还依赖 App 内厂商插件、厂商控制台证书、release 签名、用户通知权限和系统后台策略。

### 3. 强化 JPush 日志

JPush 发送失败时，日志必须包含：

- uid；
- target registration_id 数量；
- HTTP status；
- JPush response body 前 300 字符；
- third_party_channel 是否启用；
- 当前启用的第三方通道集合。

成功日志也应包含 third_party_channel 是否启用和启用通道集合，便于线上确认后端确实按预期发起了厂商通道请求。

## 数据流

1. App 启动后初始化 JPush。
2. 用户登录成功后获取 JPush registrationId。
3. App 调用 `/api/push/register` 上报 registrationId。
4. App 前后台切换时调用 `/api/push/device-state` 上报 `foreground` / `background`。
5. 后端创建通知或聊天消息时，调用 `PushService.send_to_user`。
6. 后端筛选活跃 Android registrationId，并排除最近 foreground 的设备。
7. 后端向 JPush REST API 发送 Android notification payload，带 `third_party_channel`。
8. JPush 根据设备厂商、App 内厂商插件、厂商控制台配置和签名证书尝试通过厂商离线通道投递。
9. 用户点击通知后，Flutter 的 `PushService.onOpenNotification` 解析 extras 并跳转。

## 测试策略

### Flutter / Android source-contract 测试

新增或扩展测试，检查：

- Android app module 包含厂商通道依赖关键字。
- 厂商配置不再只有华为空值读取，其它厂商也从 Gradle property / 环境变量读取。
- release buildType 不再固定 `signingConfigs.getByName("debug")`。
- MainActivity 关闭 Flutter 自动 deep link。

### 后端测试

扩展 `test_push_device_state_contracts.py`：

- JPush payload 仍包含 notification.android。
- third_party_channel 仍受配置开关控制。
- 失败/成功日志包含 third_party_channel 诊断信息。

### 验证命令

- `cd /d/FlutterProject/nonto && flutter test <push regression tests>`
- `cd /d/FlutterProject/nonto && flutter analyze`
- `cd /d/NanTuPy && .venv/Scripts/python.exe -m pytest tests/test_push_device_state_contracts.py -q`
- `cd /d/FlutterProject/nonto && flutter build apk --release --target-platform android-arm64`

## 风险与上线注意事项

1. 厂商通道需要真实厂商控制台配置。代码只能保证 APK 具备通道能力，不能替代控制台证书配置。
2. 真实验证必须使用 release 签名 APK，不能使用 debug 签名 APK。
3. Android 13+ 需要通知权限；部分国产 ROM 还需要用户允许后台运行/自启动/锁屏通知。
4. 如果极光控制台没有正确配置厂商通道证书，后端日志可能显示 JPush 接受请求，但厂商离线投递仍失败。
5. 如果厂商插件版本与 JPush SDK 版本不兼容，构建会失败；应以构建结果和极光官方可解析版本为准。

## 成功标准

- release APK 构建使用正式签名配置。
- APK 构建包含厂商通道插件依赖。
- 后端 JPush payload 和日志能明确显示第三方通道配置。
- 自动化测试和 analyzer 通过。
- 用户用真实 release 包在至少一个已配置厂商通道的真机上，App 完全后台/杀进程场景能看到系统通知栏消息。
