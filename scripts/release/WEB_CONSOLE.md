# Web 发布控制台

## 范围

Web 页面上传本地已构建的 `manifest.json` 与 `bundle.tar.gz`，选择预检、部署、重新登记或恢复，并查看持久化任务和阶段状态。本期不从浏览器执行 Git push 或 Flutter 构建，也不提供任意终端。仍使用现有数据库；新增发布任务表需要先应用后端 Alembic 迁移。

页面入口在 Web 客户端设置中。后端必须确认管理员身份、启用功能且用户 ID 位于发布允许名单；普通管理员不会自动获得发布权限。上传的后端 Python 文件是可执行代码，因此只允许可信发布人员上传，哈希校验不等于恶意代码扫描。

## 服务端准备

先由运维通过原有流程部署本次后端代码并在现有数据库执行迁移。不要指望尚未创建的任务表来执行它自己的首次安装。

后端和独立 worker 使用同一套受保护环境配置：

```dotenv
DEPLOYMENT_ENABLED=false
DEPLOYMENT_OPERATOR_IDS=
DEPLOYMENT_ARTIFACT_DIR=/www/nonto-artifacts
DEPLOYMENT_SITE_DIR=/www/wwwroot/nonto.online
```

完成运维配置后再启用并填写实际用户 ID。发布包目录必须位于网站根目录和后端代码目录之外；后端上传用户和 worker 用户需共享必要的读写权限，但不能对公众开放。限制目录权限、磁盘配额和 Nginx 请求体大小，代理上传上限不得大于后端配置。不要把包目录作为静态站点暴露。

独立 worker 代码位于客户端仓库 `scripts/release/`。将**受审查的固定版本**工具目录复制到服务器独立位置，例如 `/opt/nonto-release-tools/`，不是后端被更新的 `app/` 目录，更不是上传包里面。worker 需要现有后端 Python 环境中的 SQLAlchemy、python-dotenv 及后端依赖。

工具的 `release.config.json` 仍用于固定后端目录、Web 目录、安装包目录、状态目录、服务启停命令和备份配置。Web 页面不能修改这些命令。部署 worker 使用服务器本地执行模式，不需要向浏览器或 API 提供 SSH 私钥。worker 应使用独立系统服务，不能随 NanTuPy 服务一起停止。

```bash
/path/to/backend/python /opt/nonto-release-tools/deployment_worker.py \
  --backend-root /www/wwwroot/NonToPyDev/NanTuPy \
  --config /opt/nonto-release-tools/release.config.json
```

`--once` 仅处理至多一个任务，供运维诊断。默认持续轮询。首次创建 worker 服务、配置 sudo 白名单和确认实际 Python 路径需运维完成，工具不猜测服务名或自动配置系统服务。

`NONTO_ADMIN_TOKEN` 只在 worker 服务环境中设置，用于已经部署验证通过后的版本登记；不得放入浏览器、上传包、页面表单或日志。该令牌需要与后台发布权限分离保管并定期更新。客户端使用当前登录身份的 Bearer header，不把新发布接口 JWT 附加在 URL。

## 本地一键启动

桌面上双击 `C:\Users\25318\Desktop\NonToWebDeploy一键启动.cmd`。它会固定启动本地 FastAPI、Flutter Web 静态控制台，并打开 `http://127.0.0.1:8787/nonto/`；运行日志和 PID 记录只写入项目 `.run/deployment-console/`。停止时双击 `C:\Users\25318\Desktop\NonToWebDeploy停止.cmd`，脚本只会停止自己记录且身份匹配的 Python 进程。

首次使用或修改 Web 代码时，启动脚本会自动构建 Web。调试时可以使用项目内的 `scripts/release/一键启动Web控制台.cmd -NoBuild -NoBrowser`。如果不存在本地 `scripts/release/release.config.json`，API 和 Web 页面仍会启动，但 Worker 不会启动；固定 Worker 配置需要由运维通过受保护文件初始化，不能在 Web 表单中填写。

## Web 运行配置

`/settings/deployments` 的“运行配置”只保存非敏感设置到现有数据库：发布开关、操作员用户 ID、上传字节上限、解压字节上限和文件数量上限。页面还显示 Worker 心跳、固定错误码、队列状态和脱敏就绪状态。保存、重载都必须填写审计原因；Worker 在领取新任务前读取最新设置，运行中的任务不会被配置修改强制中断。

页面不会读取或保存 SSH 私钥、数据库密码、JWT、管理员 token、COS/SMTP/推送密钥、known_hosts、任意服务器路径或 shell 命令。服务目录、服务命令、备份命令、数据库连接和凭据继续由服务器受保护环境及固定 `release.config.json` 管理。

## 首次数据库迁移顺序

本功能复用现有 MySQL，不部署新的数据库服务，不导入本地数据库。首次启用控制台前，由运维按以下顺序执行：

1. 先部署包含后端配置 API 的代码。
2. 在现有数据库执行 `alembic upgrade head`，创建发布队列和 `deployment_settings` 表。
3. 重启 API，并确认管理员可以打开配置页。
4. 在 Web 页面填写操作员 ID、限制并显式启用发布功能。
5. 在服务器固定位置启动独立 Worker。
6. 使用 Web 控制台上传、预检、批准和执行任务。

发布后端组件时，批准步骤会要求确认 Alembic 迁移。迁移失败不会自动 `downgrade`、不会自动导入旧数据库备份，也不会自动启动旧代码；任务进入人工恢复状态。恢复旧文件前必须由运维确认当前数据库 schema 与旧代码兼容。

## 工作流

1. 本地运行原有 `package` 模式得到发布目录。
2. Web 页面选择清单和归档，填写上传原因。上传服务先校验大小、路径、组件、文件数量及 SHA-256。
3. 对发布包执行预检，查看结果。
4. 创建部署任务并确认。包含后端的任务需要明确允许在现有数据库迁移结构；恢复任务需确认旧代码与当前结构兼容。
5. 独立 worker 复查当前角色和允许名单，执行固定 runner。页面轮询阶段和脱敏错误码。
6. 部署、健康检查和公网产物验证成功后才登记版本。登记失败可单独创建 register 任务，不重复执行部署。

## 失败与恢复

- 页面退出不会取消任务，重新进入可查看历史记录。
- 只有排队或待确认任务能取消；运行中的数据库迁移不得强杀。
- worker 使用进程锁避免同机重复 worker。只能为一个数据库配置一个 active worker/状态目录，多机同时运行不受支持。
- worker 启动时将遗留 running/verifying 状态标为 `manual_recovery`，绝不重放尚不确定的部署。存在未恢复任务时暂停后续部署。
- 确认兼容后的 restore 任务可以恢复同一发布包涉及的文件；成功后解除该发布包的人工恢复阻塞。不会执行数据库 downgrade 或导入旧备份。
- 若服务已停止，Web API 可能暂时不可用。页面无法替代 SSH 运维通道；必要时运维应使用固定 runner 恢复服务，再核对任务状态。不要直接重跑 deploy。
- 日志只返回固定阶段、错误码和时间。原始子进程输出、备份内容和路径不通过 API 返回。

## 验证与限制

自动测试使用 SQLite、临时目录和模拟执行器，不连接生产 SSH、不迁移真实数据库、不推送仓库。现有本地后端 `app/debug_agent_log.py` 的编码问题仍会被打包器阻止，需在正式构建前处理。

本功能不宣称包内容通过防病毒引擎扫描，生产网关如有要求需另接可信扫描服务。首次迁移、worker 系统服务、权限及真实 HTTPS/公网安装包验证均需要部署环境验收。
