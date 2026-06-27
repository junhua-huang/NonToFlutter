# Remaining UX, Identity, Unread, and Chat Reliability Fixes Design

日期：2026-06-27

## 背景

用户原始反馈包含 6 类问题：

1. 首页推荐流头像 UI 与发现页、会话页不一致。
2. 设置页身份认证无法选择身份；身份认证入口希望放到抽屉栏；身份认证支持用户提交 0-9 张图片；提交后需要乐观更新；后端收到身份认证申请后发邮件到 `2531830689@qq.com` 提醒管理员审核。
3. 搜索结果页搜索框左边需要返回按钮，点击后退出搜索状态。
4. 未读消息数统计不准确：通知入口没有正确气泡，通知列表有未读通知，底部消息 Tab 却统计了通知未读。
5. 群聊发消息重复显示、时间显示错误；私聊旧消息时间错误，并且旧消息错误地停在聊天室底部。
6. 底部导航栏未读消息气泡颜色要与会话列表未读气泡颜色一致。

此前只完成或设计了部分聊天/未读问题；当前源码核对显示仍存在未完成项：

- `home_screen.dart` 仍把通知未读与聊天未读相加显示到底部消息 Tab。
- `messages_tab.dart` 通知入口仍维护本地 `_unreadNotifications`，未完全复用通知 provider。
- 首页 Feed 顶部头像尺寸与 `NontoHeaderSearchBar` 中头像不一致。
- 身份认证页仍是图片链接文本框，不是 0-9 张图片选择/上传。
- 抽屉栏没有身份认证入口。
- 搜索结果状态没有搜索框左侧返回按钮。
- 后端 `roles.py` 已能保存申请和 `proof_images`，但没有管理员邮件提醒。

两个项目路径：

- Flutter 前端：`D:/FlutterProject/nonto`
- FastAPI 后端：`D:/NanTuPy`

当前两个目录都未发现 `.git`，因此本轮可写文档和代码、运行验证，但不能提交 git commit。

## 目标

1. 首页推荐流、发现页、消息页顶部头像视觉一致。
2. 抽屉栏和设置页都能进入身份认证。
3. 身份认证页可以选择业务身份，支持 0-9 张证明图片。
4. 身份认证提交后前端立即展示“已提交/等待审核”的乐观状态。
5. 后端身份认证申请提交成功后，向管理员邮箱 `2531830689@qq.com` 发送审核提醒。
6. 搜索结果状态下，搜索框左侧显示返回按钮，点击后清空结果并退出搜索状态。
7. 底部消息 Tab 未读气泡只统计聊天会话未读，不再叠加通知未读。
8. 消息页“通知消息”入口使用通知 provider 的未读数，与通知列表一致。
9. 所有未读气泡使用统一语义色 `AppColors.unreadBadge`。
10. 继续补齐群聊/私聊消息时间、去重、排序的缺口，确保旧消息不会因时间解析失败停在底部。

## 非目标

- 不重做整套首页/发现页/消息页导航架构。
- 不重构完整身份审核后台 UI。
- 不引入新的文件选择依赖，优先使用现有 `image_picker`、`cross_file`、`UploadService`。
- 不让邮件发送失败阻塞身份认证提交。
- 不改变现有已认证身份展示模型，只补申请入口、图片和提醒流程。
- 不做大规模聊天架构重写；本轮只修复去重、时间解析、排序和未读统计的根因缺口。

## 设计

### 1. 顶部头像 UI 统一

现状：

- 首页 `FeedTab` 顶部 AppBar leading 使用 `NontoHeaderAvatar(radius: 10)`。
- 发现页和消息页通过 `NontoHeaderSearchBar` 使用 `NontoHeaderAvatar(radius: 18)`。

设计：

- 首页 Feed 顶部头像改为与 `NontoHeaderSearchBar` 相同的头像视觉尺寸和点击热区。
- 优先复用 `NontoHeaderAvatar`，统一半径为 18。
- 保留首页标题 `NonTo` 和抽屉打开行为。
- 如需要额外 padding，按发现页/消息页搜索栏左侧头像间距对齐。

验收：

- 首页、发现页、消息页顶部当前用户头像半径一致。
- 首页头像点击仍打开抽屉栏。

### 2. 身份认证入口与页面

现状：

- 设置页已有“身份认证”入口。
- 抽屉栏没有身份认证入口。
- `IdentityApplicationScreen` 使用 `DropdownButtonFormField` 选择角色，但图片证明是文本框输入 URL。

设计：

- 抽屉栏新增 `身份认证` 菜单项，图标使用 `Icons.verified_outlined`，点击后关闭抽屉并打开 `AppRoutes.identityApplication`。
- 设置页入口保留。
- 身份认证页加载 `/api/roles` 后展示业务身份选项。
- 若角色列表为空，显示错误/空态，提交按钮禁用。
- 身份选择使用明确的 `value` 而不是只依赖易出兼容问题的旧属性。
- 支持选择 0-9 张证明图片：
  - 使用现有 `image_picker` 多图选择能力或逐张选择能力。
  - 用户可预览缩略图。
  - 用户可删除已选图片。
  - 达到 9 张后禁用继续添加。
  - 允许 0 张图片提交。
- 提交时：
  - 先上传已选图片，得到 URL 列表。
  - 调用 `RoleService.applyIdentity(proofImages: uploadedUrls, ...)`。
  - 提交中禁用表单与按钮，避免重复提交。
  - 成功后立即展示“认证申请已提交，等待管理员审核”，并返回上一页或刷新本地申请状态。
  - 失败时恢复表单，并保留用户输入和已选图片。

乐观更新：

- 成功响应返回前不授予已认证身份。
- 提交 API 成功后，前端立即把当前申请状态作为本地 pending 状态展示，避免用户返回后看不到变化。
- 若后续拉取 `listMyApplications`，以后端状态为准。

验收：

- 用户可以切换身份。
- 0 张图片可以提交。
- 9 张图片可以提交。
- 第 10 张图片不能继续添加或会提示最多 9 张。
- 提交失败不丢失填写内容。
- 抽屉栏和设置页都能进入身份认证。

### 3. 后端身份认证邮件提醒

现状：

- `D:/NanTuPy/app/routers/roles.py` 已有 `POST /api/roles/apply`。
- `RoleApplyRequest` 已接收 `proof_images`。
- `RoleApplication` 已保存 `proof_images`。
- `D:/NanTuPy/app/services/email_service.py` 已有通用 `EmailService.send_email()`。

设计：

- 在配置中增加管理员审核提醒邮箱：

```python
ROLE_REVIEW_ADMIN_EMAIL = os.environ.get(
    "ROLE_REVIEW_ADMIN_EMAIL",
    "2531830689@qq.com",
)
```

- `apply_role()` 创建申请并提交成功后，异步触发邮件提醒。
- 邮件主题示例：`【南图】新的身份认证申请待审核`。
- 邮件正文包含：
  - 申请 ID；
  - 用户 ID、用户名、邮箱；
  - 申请身份名称和标签；
  - 认证说明；
  - 联系方式；
  - 证明图片数量和 URL 列表；
  - 作品链接；
  - 补充说明；
  - 提交时间。
- 邮件发送失败只记录 warning，不回滚申请、不让接口失败。
- 后端限制 `proof_images` 长度为 0-9，超过 9 返回 422/400。

验收：

- 身份申请成功后会调用邮件服务。
- 邮件目标默认是 `2531830689@qq.com`。
- SMTP 未配置或发送失败时，接口仍返回申请成功。
- 超过 9 张证明图片被后端拒绝。

### 4. 搜索结果页返回按钮

现状：

- `SearchTab` 中搜索结果由 `_isSearching` 控制。
- 搜索结果内容 `_buildSearchResults()` 没有返回按钮。
- 顶部 `NontoHeaderSearchBar` 左侧默认是头像或搜索 icon。

设计：

- 扩展 `NontoHeaderSearchBar` 支持可选 `leading` 或 `showBackButton`。
- 在 `SearchTab` 的搜索结果状态，即 `_isSearching == true` 时，搜索框左侧显示返回按钮。
- 返回按钮点击调用 `_exitSearchMode(clearResults: true)`。
- 退出时：
  - 清空输入；
  - 清空搜索结果；
  - 恢复 `_inSearchMode = false`；
  - 恢复默认发现页；
  - 恢复全局顶部栏显示。

验收：

- 搜索结果页搜索框左侧能看到返回按钮。
- 点击返回按钮退出搜索状态，回到默认发现页。
- 不影响话题搜索独立页面已有 AppBar 返回行为。

### 5. 未读统计与气泡颜色

现状：

- `HomeScreen` 中底部消息 Tab badge 使用：

```dart
unreadNotificationsCountProvider + unreadMessagesCountProvider
```

- `MessagesTab` 通知入口使用本地 `_unreadNotifications`。
- 会话气泡直接用 `AppColors.likeRed`。
- 底部 `Badge` 未显式使用同一颜色 token。

设计：

- `HomeScreen` 底部消息 Tab badge 只读取 `unreadMessagesCountProvider`。
- 通知未读不参与底部消息 Tab 统计。
- `MessagesTab` 删除本地 `_unreadNotifications` 状态和单独 API 拉取，改为读取通知 provider：
  - 优先 `unreadNotificationsCountProvider`；或
  - 直接 `notificationsProvider.unreadCount`。
- 刷新消息页时可触发通知 provider 刷新，但显示值以 provider 为准。
- `AppColors` 增加：

```dart
static const Color unreadBadge = likeRed;
```

- 会话列表未读气泡、通知入口气泡、底部导航气泡全部使用 `AppColors.unreadBadge`。
- 底部 `Badge` 明确设置 `backgroundColor: AppColors.unreadBadge`。

验收：

- 只有通知未读、没有聊天未读时，底部消息 Tab 不显示 badge。
- 通知列表有未读时，消息页“通知消息”入口显示 badge。
- 聊天会话有未读时，底部消息 Tab 显示 badge。
- 底部 badge、通知入口 badge、会话列表 badge 颜色一致。

### 6. 群聊/私聊消息去重、时间与排序

已有基础：

- 前端已有 `test/chat_time_and_community_dedupe_regression_test.dart`。
- 后端已有 `test_community_chat_contracts.py` 覆盖部分 `client_msg_id`、UTC `Z` 时间格式、mark-read 逻辑。
- 设计文档 `2026-06-26-critical-chat-unread-bugs-design.md` 已描述统一时间解析和 `client_msg_id` 合并策略。

本轮继续核对并补齐：

- 群聊发送请求必须带 `client_msg_id`。
- 群聊 HTTP 响应和 WebSocket 回显必须携带同一个 `client_msg_id`。
- 前端合并顺序：
  1. 相同 `client_msg_id` 替换乐观消息；
  2. 相同服务端 `id` 更新已有消息；
  3. 如果服务端消息和乐观消息同时存在，删除乐观消息；
  4. 最后才使用旧的内容/发送者模糊匹配。
- 私聊和群聊统一使用 `AppDateUtils.parseServerTime()`。
- 无时区时间按 UTC 解析。
- 非法时间返回 `null`，历史消息排序不 fallback 到 `DateTime.now()`。
- 排序 fallback 优先使用服务端 ID/稳定原始顺序，而不是当前时间。

验收：

- 群聊发送一条消息最终只显示一条。
- WS 先到、HTTP 后到不会重复。
- HTTP 先到、WS 后到不会重复。
- 私聊收到很早以前的旧消息，时间显示正确或合理兜底，不会固定在列表底部。
- 新发消息仍能排到最新位置。

## 测试计划

### Flutter 新增/修改测试

- `test/remaining_ux_identity_unread_regression_test.dart`
  - 首页头像 radius 与 `NontoHeaderSearchBar` 一致。
  - 抽屉栏包含身份认证入口。
  - 身份认证页不再使用“证明图片链接”文本框。
  - 身份认证页包含最多 9 张图片限制。
  - 搜索结果状态有返回按钮并调用 `_exitSearchMode(clearResults: true)`。
  - 底部消息 Tab 只读取 `unreadMessagesCountProvider`。
  - `MessagesTab` 通知入口读取通知 provider，不维护 `_unreadNotifications`。
  - 未读 badge 使用 `AppColors.unreadBadge`。

继续运行：

- `flutter test test/chat_time_and_community_dedupe_regression_test.dart`
- `flutter test test/notification_ux_regression_test.dart`
- `flutter test test/permissions_and_unread_regression_test.dart`
- `flutter test test/role_identity_contract_test.dart`
- `flutter analyze`

### 后端新增/修改测试

- `tests/test_role_identity_email_contracts.py`
  - `RoleApplyRequest` 限制 `proof_images` 0-9。
  - 配置包含 `ROLE_REVIEW_ADMIN_EMAIL` 默认值。
  - `apply_role` 成功后调用邮件提醒。
  - 邮件发送失败不阻塞申请成功。
  - 邮件正文包含申请人、身份、图片和联系方式信息。

继续运行：

- `python -m pytest tests/test_role_identity_email_contracts.py -q`
- `python -m pytest tests/test_community_chat_contracts.py tests/test_chat_read_state_contracts.py tests/test_notification_service_unit.py -q`

## 实施顺序

1. 写 Flutter 和后端 RED 回归测试。
2. 修 Flutter 主题色、未读统计、通知入口 provider。
3. 修顶部头像和搜索返回按钮。
4. 修身份认证前端入口、图片选择/上传、乐观 pending 状态。
5. 修后端 `proof_images` 0-9 校验和管理员邮件提醒。
6. 复核聊天去重/时间/排序现有实现，补缺口。
7. 运行聚焦测试。
8. 运行 `flutter analyze`、后端相关 pytest。
9. 如测试失败，按失败输出继续定位，不做完成声明。

## 回滚策略

- 未读统计变更可单独回滚到旧 provider 订阅，但不建议恢复通知+聊天相加。
- 身份认证图片上传只影响申请页；后端仍接受旧 `proof_images` URL 数组。
- 邮件提醒失败不影响主流程，因此可通过环境变量禁用或留空 SMTP 配置。
- 搜索返回按钮只影响搜索结果状态。
- 聊天时间和去重逻辑保留旧模糊匹配 fallback，降低兼容风险。
