# Windows → GitHub → TestFlight 内部测试

此流程打包原生 `NonToFlutter/ios`，连接 `https://www.nonto.online/api` 和 `wss://www.nonto.online/ws`；App ID 为 `online.nonto.native`，Apple Team 为 `B2Y3564MKK`。无需本机安装 Xcode。上传和实际可安装是不同阶段；只有 Apple 处理完成并加入内部测试组后，测试者才可在 TestFlight 安装。

## 1. Apple 后台准备

- 在 Apple Developer 为 App ID 开启 Push Notifications。App Store Connect 已创建匹配的 iOS 应用记录；账号协议已由账号持有人自行确认。
- 在 App Store Connect 的“用户与访问 → 集成 → App Store Connect API → 团队密钥”创建专用密钥。自动生成发行证书和描述文件需要 Admin 权限；团队密钥覆盖账号全部应用，请只放在本仓库的 Actions Secrets，不公开分享。
- 这不是 APNs 密钥。APNs `.p8` 保留在 Python 服务器，不能用于签名或上传。iOS 安装包也不包含任何私钥。

## 2. 配置仓库 Secrets

打开 GitHub 仓库 `junhua-huang/NonToFlutter` → Settings → Secrets and variables → Actions → New repository secret，添加：

| 名称 | 值 |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect 团队密钥的 Key ID |
| `ASC_ISSUER_ID` | 同一账号页面的 Issuer ID |
| `ASC_PRIVATE_KEY` | 对应 `.p8` 文件的完整 PEM 文本，包括 BEGIN/END 行与真实换行 |

不要上传 `.p8` 到仓库或 Issue。密钥不可用时验证任务只编译检查，上传任务跳过；不会把验证成功说成上传成功。

## 3. 触发内部上传

仓库的 `TestFlight Internal` 工作流只处理 `ios` 分支。以 `[testflight]` 为标记的提交触发内部发布；其他提交不会自动上传。

首次流程提交会生成一条验证运行。添加 Secrets 后，打开 Actions → TestFlight Internal → 对应最新代码的运行 → Re-run all jobs。重试会重新读取当前 Secrets，并使用新的构建号。

以后可在 Windows 的 Git 终端中执行：

```sh
git switch ios
git pull --ff-only origin ios
git commit --allow-empty -m "[testflight] Upload internal build"
git push origin ios
```

如果工作流已在仓库默认分支注册并显示 Run workflow，也可手动运行并选择 `ios`。GitHub 的 workflow_dispatch 有默认分支要求，所以此流程同时支持提交触发与重试，无需为了发布修改其他平台的默认分支。

## 4. 云端执行与限制

- 验证 Python 发布检查、生成工程一致性及 Xcode 26 的 internal-only 导出能力，先做未签名的内部归档检查。
- 获取此 App 的已有记录，验证 Push Notifications 能力，创建本次运行专用的 Apple Distribution 证书和 App Store 描述文件。验证团队、App ID、证书关联、有效期和 `aps-environment=production`，使用临时 Keychain 签名。
- Release 归档明确设置 `NONTO_DISTRIBUTION_CHANNEL=testflight-internal`，保留开发测试提示。普通 App Store Archive 仍执行严格发布检查；不伪造运营资料、备案或服务器验证结果。
- Xcode 的 `testFlightInternalTestingOnly=true` 限制上传构建只用于内部测试，不能转作外部 TestFlight 或 App Store 正式提交。此限制不表示 App 已完成法律、内容治理或正式发布合规审核。
- 构建号为本工作流运行序号和重试次数，例如 `1.2`。当前 App 版本为 `1.0.0`。构建号冲突时新建带标记提交；不要反复用同一个已上传构建号。
- 当前原生 App 的网络和安全存储依赖 Apple 系统能力，仅使用系统加密与摘要，没有自有非豁免加密实现；Info.plist 的 `ITSAppUsesNonExemptEncryption=false` 对应这一范围。新增自有加密、第三方加密库或业务变化时，应重新核对 Apple 出口合规问题，不能沿用未复核的声明。
- 上传后最多等待约 10 分钟查询 Apple processingState。`VALID` 才报告处理完成；失败或超时不声称可安装。没有自动邀请测试者、创建外部公开链接或提交正式审核。
- 正常完成后，仅删除本次创建的描述文件和发行证书，不触碰其他 App 的现有证书。证书额度已满时失败并要求维护者处理，绝不自动撤销已有证书。
- 如果上传结果或 Apple 处理状态不确定，保留本次 Apple 资源，避免撤销证书使正在处理的上传失效。日志打印资源 ID，待 Apple 处理完成后可在 Apple Developer 手动核对并清理这些临时资源。强制终止任务也可能需要手动清理。临时私钥、P12 和 Keychain 不作为 artifact 上传，runner 结束时销毁。

## 5. 在 iPhone 安装并验证 APNs

工作流确认 Apple 处理完成后，打开 App Store Connect → 南图 → TestFlight → 内部测试，创建或选择内部测试组，把该构建和自己的 App Store Connect 用户加入组。按页面要求补齐测试资料、处理提示；在 iPhone 安装 Apple TestFlight 并用获邀账号安装南图。此内部构建不能邀请账号外的普通外部测试者。

在南图“设置 → 消息提醒”开启系统通知和系统推送、保存，等待设备绑定后点“发送远程测试通知”。本地测试不能证明 APNs 接通。退到桌面或锁屏后，再验证另一账号的私信提醒、点击进入会话、退出解绑和不重复提醒。Production 密钥用于这种发行签名的 App；开发签名对应 Sandbox，不能混用。

## 验证边界

未配置 Secrets 时，只能验证脚本、编译和未签名归档。自动签名、Apple API 权限、证书额度、上传与真机投递必须在实际账号配置后验证，不能用 mock 测试代替。云端验证通过也不会自动解决 `COMPLIANCE.md` 中的正式发布待办。

参考：[Apple API 密钥](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)、[创建证书](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-certificates)、[创建描述文件](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-profiles)、[内部测试](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)、[系统加密出口说明](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)。
