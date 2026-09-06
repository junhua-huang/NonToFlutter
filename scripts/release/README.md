# NonTo 一键发布

用于 Windows 本地构建和通过 SSH 发布到宝塔非 Docker 环境。默认只预览，不连接服务器。本次脚本开发没有执行线上发布。

## 数据库边界

继续使用服务器现有数据库及后端 `.env` 连接配置。脚本不安装 MySQL、不新建或替换数据库服务、不导入本地数据库。

新版本需要新增表、字段或索引时，在现有数据库上执行 `alembic upgrade head`。迁移前备份；迁移失败可能已提交部分 MySQL DDL，因此不得自动 downgrade 或恢复旧数据库覆盖业务数据。迁移文件自身需要经过审核，Alembic 不保证所有变更都无损。

## 首次配置

从 `release.config.example.json` 建立本地 `release.config.json`，该文件已加入忽略规则：

- `server.user`、`identity_file`、`known_hosts_file`：实际 SSH 用户、私钥和已核实指纹的 known_hosts 文件。工具使用 StrictHostKeyChecking，不自动接受新指纹。
- `python_executable`：服务器现有后端环境的 Python 绝对路径。
- `stop_command`、`start_command`：实际进程管理器命令，采用 argv 数组。模板留空，不能猜测服务名。启动命令不得自行重建数据库或重复执行迁移。
- `service_environment_confirmed`：核实服务与迁移使用相同的 `.env`、环境变量和数据库后，设为 `true`。
- `database_backup_credentials_file`：网站目录以外的受保护 MySQL 客户端配置文件，不含在发布包中。
- `database_backup_command`：例如 `["mysqldump", "--defaults-extra-file=/实际路径/mysql-client.cnf", "--single-transaction", "实际现有库名"]`。不要在参数中写密码。备份权限和数据库范围必须与后端实际数据库一致。
- `android`：配置 `apksigner`、`aapt`、正式证书 `certificate_sha256` 和包名。客户端 `android/key.properties` 必须指向正式签名，Debug 证书不允许发布。
- `publish`：填写更新说明、渠道、最低支持构建号和公开站点地址。发布平台由 `-Components` 控制。

服务目录和下载目录需要事先存在且发布用户可写。`state_dir` 必须位于整个网站根目录以外；保留备份和部署日志，不会自动清理。

默认位置：

| 用途 | 路径 |
| --- | --- |
| 后端 | `/www/wwwroot/NonToPyDev/NanTuPy` |
| Web | `/www/wwwroot/nonto.online/nonto/` |
| 安装包 | `/www/wwwroot/nonto.online/downloads/` |
| 状态和备份 | `/www/nonto-releases/` |

Web 路径末尾的 `/` 必须保留。`/downloads/` 需要配置为真正的静态文件目录；返回首页的 HTTP 200 不算安装包验证成功。

## 使用

在项目根目录 `E:\FlutterProject\nonto` 的 PowerShell 中运行：

```powershell
# 仅预览；可以直接使用模板，不连接服务器、不写文件
.\scripts\release\一键发布.cmd -Mode plan -Config .\scripts\release\release.config.example.json

# 本地测试并构建 Release 包，不上传
.\scripts\release\一键发布.cmd -Mode package -Components backend,web,android

# 使用当前版本自动打包、发布并登记更新
.\scripts\release\一键发布.cmd -Mode deploy -Components backend,web,android

# 指定新构建版本；只覆盖本次产物版本，不修改 pubspec.yaml
.\scripts\release\一键发布.cmd -Mode package -Version 1.0.2+3 -Components backend,web,android,windows

# 发布已生成的包；把 release-id 换成 package 输出的目录名称
.\scripts\release\一键发布.cmd -Mode deploy -Release .\scripts\release\out\release-id

# 已部署成功但管理员版本登记失败，只重试验证与登记
.\scripts\release\一键发布.cmd -Mode register -Release .\scripts\release\out\release-id

# 已人工确认旧代码兼容当前数据库结构后，恢复应用文件（不恢复数据库）
.\scripts\release\一键发布.cmd -Mode restore -Release .\scripts\release\out\release-id -SchemaCompatible
```

入口使用本机 `py -3`，其次 `python3` 或 `python`；须安装可用 Python，不能使用 WindowsApps 占位程序。后端测试使用 `D:\NanTuPy\.venv\Scripts\python.exe`。本地后端源码位置为 `D:\NanTuPy`。

更新登记需要在当前终端设置 `NONTO_ADMIN_TOKEN`，它只通过 HTTPS Authorization 请求头发送。不要提交令牌、把令牌写进配置，或附加到 URL。管理接口需要预先登录取得的管理员令牌。

若服务器尚未应用 `app_releases` 迁移，先使用 `-Mode deploy -Components backend` 更新后端并迁移现有数据库，再发布客户端。后端单独发布不要求版本表预先存在。客户端发布会先验证管理员接口，不能绕过失败继续发布。

## 检查与恢复

- 本地检查、测试、Release 构建后生成逐文件 SHA-256 清单及压缩包。Web 使用 `/nonto/` base href，不发布 `.map`、`.symbols` 和嵌套 ZIP。
- Android 验证正式签名、包名、版本名和构建号。Windows ZIP 包含完整 Release 目录，不是单个 EXE。
- 远端校验路径、归档及哈希，备份发布涉及的应用文件和现有数据库，再迁移及切换代码。`.env`、上传、运行日志、虚拟环境和其他非发布文件不应被覆盖。
- 健康检查要求 JSON 同时包含 `status=healthy` 和 `database=connected`，不能只检查 HTTP 200。公网 Web 版本和安装包哈希通过后，才登记更新。
- 迁移开始后的任何发布失败都停止服务并要求人工恢复，不自动启动旧代码。`-SchemaCompatible` 表示已经人工确认旧代码兼容当前数据库结构，仅用于文件恢复；它不会回滚数据库。未进入迁移的失败可自动恢复本次涉及的文件。
- 包、清单和当前脚本必须保留，`register`/`restore` 会核对服务器已上传的配置和脚本哈希。脚本升级后不要盲目重试旧部署。
- 不自动安装或替换生产 Python 依赖环境。新依赖不满足时应停止，由运维先准备与服务一致的环境。

测试全部使用临时目录或模拟命令，不需要连接生产服务器：

```powershell
D:\NanTuPy\.venv\Scripts\python.exe -m pytest scripts\release -q
```

## 已发现的本地打包阻碍

后端 `app/debug_agent_log.py` 包含空字节（UTF-16 样式编码），不能被 Python 正常解析。发布器会报告具体文件并停止，不能将该错误解释为已成功构建或部署。此脚本任务没有修改这个既有后端文件。
