# Windows → GitHub → TestFlight 内部测试

原生 App 连接 `https://www.nonto.online/api` 和 `wss://www.nonto.online/ws`；Bundle ID 为 `online.nonto.native`，Team 为 `B2Y3564MKK`。Windows 可完成一次性签名配置，GitHub 的 macOS runner 负责构建和上传。

## 签名资源长期复用

`IOS_SIGNING_KEY` 是发行证书配套的长期 RSA 私钥。日常发布通过 Apple API 按公钥查找匹配的有效发行证书，再获取该 App 对应的、已经验证过的描述文件。**普通上传不会创建、撤销或删除 Apple 证书与描述文件。**

仅显式触发 `[signing-setup]`（或手动运行时勾选初始化）才允许创建缺失或已失效的资源。即使重复初始化，已有有效匹配资源也会复用。初始化请求中断后，可用同一私钥再次查找已创建的证书，避免换私钥重复申请。

旧版临时方案中，runner 结束时已销毁临时私钥。Apple 只能重新下载公有证书，不能恢复私钥；因此缺少原配私钥的旧证书不能直接用于重新签名。如果你保存了现成的发行 P12，可以导入其中的私钥并复用对应证书。

## Windows 配置助手

新建 Apple Distribution 身份使用 **RSA 2048**。早期辅助脚本生成的 RSA 3072 私钥可能被 Apple 的 CSR 校验拒绝。遇到该情况，下载当前版本的 Windows 辅助脚本，运行一次修复：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\NonToAppleConnect\setup_signing.ps1 -RepairUnsupportedKeySize
```

修复模式会先在本机保存旧密钥备份，再创建 RSA 2048 私钥，并更新 **本仓库**的 `IOS_SIGNING_KEY`（无 GitHub CLI 时打开现有 Secret 编辑页，粘贴后点 Update secret）。重复修复会复用已兼容的本机密钥。备份已存在时拒绝覆盖；脚本不会调用 Apple API。

也可以将仓库中的 `ios/scripts/setup_signing.ps1` 下载到 `C:\NonToAppleConnect`，在 PowerShell 运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\NonToAppleConnect\setup_signing.ps1
```

此执行策略参数只作用于这一次进程，不修改系统策略。助手使用本机 Python 3，缺少 cryptography 时安装依赖。已有本地签名私钥会保留；GitHub CLI 已登录并有该仓库 Secrets 权限时，会直接保存 `IOS_SIGNING_KEY`；否则复制私钥到本机剪贴板并打开该仓库的新建 Secret 页面，你只需填名称、粘贴并保存。它不会登录其他账号，也不会创建或撤销 Apple 证书。已有同名 Secret 时，CLI 模式会保留该 Secret 并停止，不会覆盖未知的签名身份。

已有发行 P12 时，可用 `-ImportP12 C:\路径\Distribution.p12` 导入（需在本机输入 P12 密码，且目标目录不得已有签名私钥）。完成 Secret 保存后，再运行下面的签名初始化；旧证书额度或冲突仍需先核对处理。

## 1. 一次性准备长期签名私钥

在 Windows 上更新本仓库的 `ios` 分支，打开仓库目录的 PowerShell，执行：

```powershell
python -m pip install "cryptography>=45,<47"
python ios/scripts/create_signing_key.py --output C:\NonToAppleConnect\NonToDistribution.key
```

脚本只在本机生成 RSA 私钥，不访问 Apple，不创建证书，不显示私钥内容。输出文件已存在时拒绝覆盖，避免意外更换签名身份。请保留安全备份。

如果已有包含私钥的发行 `.p12`，改用：

```powershell
python ios/scripts/create_signing_key.py --from-p12 C:\NonToAppleConnect\Distribution.p12 --output C:\NonToAppleConnect\NonToDistribution.key
```

按提示在本机输入 P12 密码（输入隐藏）。不能用只有公钥的 `.cer`、APNs `.p8` 或 App Store Connect `.p8` 替代签名私钥。

## 2. 只配置一次 Actions Secrets

打开 GitHub 仓库 `junhua-huang/NonToFlutter` → Settings → Secrets and variables → Actions。

| Secret | 内容 |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect 团队 API Key ID，已有配置可继续使用 |
| `ASC_ISSUER_ID` | 同一账号的 Issuer ID，已有配置可继续使用 |
| `ASC_PRIVATE_KEY` | 对应 App Store Connect `.p8` 完整 PEM，已有配置可继续使用 |
| `IOS_SIGNING_KEY` | 上一步本机 `NonToDistribution.key` 的完整 PEM，包含 BEGIN/END 行和真实换行 |

可在本机复制签名私钥：

```powershell
Get-Content -Raw C:\NonToAppleConnect\NonToDistribution.key | Set-Clipboard
```

把剪贴板内容粘贴到新的 `IOS_SIGNING_KEY` Secret。不要发到聊天、Issue 或提交到仓库。APNs 私钥继续保留在 Python 服务器，本方案不更换 APNs Key。

当前初始化需要有证书和描述文件管理权限的 API Key；此前配置的专用 Admin 团队密钥可以使用。普通上传只查询签名资源，但上传权限仍须满足 Apple 要求。

## 3. 只读检查与首次初始化

先确认 Apple Developer 的 App ID 已开启 Push Notifications，App Store Connect 中已存在匹配的应用记录，并已处理账号协议。

只读检查不需要 `IOS_SIGNING_KEY`，可以立即执行：

```powershell
git switch ios
git pull --ff-only origin ios
git commit --allow-empty -m "[signing-check] Inspect reusable signing resources"
git push origin ios
```

该运行只查询发行证书的 ID、序列号和到期时间、此 App 的描述文件，以及已有构建的处理状态；不会创建或删除资源。配置了 `IOS_SIGNING_KEY` 时，还会为同团队、未过期且匹配该密钥的发行证书输出 `App filing certificate`：包含 Bundle ID、证书 ID、证书 SHA-1 和十六进制 PKCS#1 公钥，可用于准备 iOS 备案特征信息。应与成功构建的 `TF_SIGNING_IDENTITY`（证书 SHA-1）核对，不能把其他证书或公钥的 SHA-256 当作签名 SHA-1。Apple API 错误会输出错误码和已识别的原因，不打印原始响应、私钥或 JWT。

配置好长期私钥后，首次初始化并上传：

```powershell
git commit --allow-empty -m "[signing-setup] Initialize reusable signing and upload internal build"
git push origin ios
```

如果 Apple 报证书额度或现有证书冲突，先根据只读检查结果在 Apple Developer 核对旧证书的用途，再处理确实不再使用的证书。不能靠反复点击重跑释放额度，本流程也不会自动撤销证书。旧临时描述文件的名称为 `NonTo-TF-<旧运行ID>-<尝试次数>`；新的长期描述文件名称以 `NonTo-TestFlight-<证书ID>-` 开头。

## 4. 以后发布

以后只需：

```powershell
git switch ios
git pull --ff-only origin ios
git commit --allow-empty -m "[testflight] Upload internal build"
git push origin ios
```

已有签名资源直接复用。若证书、私钥或描述文件不匹配，或资源已过期，普通发布会在归档签名前停止，并给出初始化/续期提示，不会隐式创建替代资源。

手动 Run workflow（在默认分支注册后可见）选择 `ios` 即可，日常发布不勾选初始化。重跑旧运行会使用该运行原有的旧版脚本；迁移到本方案后请运行包含本次修复的新提交。

缺少任一 Secret 时，只做未签名验证，上传跳过，Actions 摘要列出缺少的名称；不能把验证通过当成上传成功。

## 5. 云端验证与清理

- 运行发布脚本测试、生成工程一致性检查及 Xcode 26 内部归档检查。
- 验证证书与私钥公钥匹配、团队、有效期，以及描述文件的团队、Bundle ID、证书关联、有效期和 production APNs 权限。
- 临时 P12 和 Keychain 只用于本次 runner 的导入；证书和配套私钥本身保持不变，P12 不上传为 artifact。
- Release 归档设置 `NONTO_DISTRIBUTION_CHANNEL=testflight-internal`；保留开发测试说明。普通 App Store Archive 继续执行严格发布检查，不伪造运营资料、备案或服务端验证结果。
- `testFlightInternalTestingOnly=true` 只允许内部测试，不用于外部 TestFlight 或 App Store 正式发布。
- 构建号使用工作流运行序号与尝试次数，如 `7.1`。上传成功立即写入摘要，然后独立等待 Apple 处理。暂时性连接故障会重试，只有 `VALID` 才报告处理完成。
- 清理只移除当前 runner 安装的描述文件副本、临时私钥容器和 Keychain，不调用 Apple 删除接口，也不依赖 Apple 状态查询能否成功。GitHub Secret 里的长期私钥和 Apple 上的签名资源保留以供下次发布。

## 6. iPhone 安装与 APNs 真机验证

Apple 处理完成后，在 App Store Connect → 南图 → TestFlight → 内部测试，把构建加入测试组并添加自己的账号；按页面要求补齐测试资料。在 iPhone 的 TestFlight 接受邀请并安装。本流程不自动发送测试者邀请。

在南图“设置 → 消息提醒”开启通知并保存，设备绑定后点击“发送远程测试通知”。本地测试不能证明 APNs 已接通。退到桌面或锁屏后，继续验证另一账号的私信提醒、点击进入会话、退出解绑和不重复提醒。

当前 `ITSAppUsesNonExemptEncryption=false` 对应仅使用 Apple 系统加密和摘要的原生 App；新增加密实现时需重新审核。内部构建不表示已完成 `COMPLIANCE.md` 的正式发布待办。

参考：[Apple 证书查询](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-certificates)、[描述文件查询](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-profiles)、[API 密钥](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)、[内部测试](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)、[GitHub Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)。
