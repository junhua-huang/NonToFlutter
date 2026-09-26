# Post Share Target Cache and Conversation Sorting Design

## Goal

帖子分享到聊天面板应从缓存层维护的分享对象数据中快速展示目标，并把好友与社群混排成一个列表。混排顺序以会话列表顺序为准，近期会话目标优先，未出现在会话列表中的目标排在后面。

## Current State

- `CacheKeys.friendList` 已存在，当前 key 为 `friend:list`。
- 分享面板 `PostShareToChatSheet` 当前直接请求 `FriendService().getFriends()` 和 `CommunityApiService().getMy()`，没有优先读取缓存。
- 我的社群列表没有独立缓存 key。
- 会话列表缓存为 `CacheKeys.convFullList`，其顺序即消息页会话列表展示顺序。
- 分享面板当前分组展示：先好友，再社群；每组内部保持接口顺序。

## Target Behavior

分享面板展示一个混合分享对象列表：

1. 好友和社群在同一个列表中展示。
2. 已存在会话的对象按 `conv:full:list` 的顺序排列。
3. 没有对应会话的对象排在所有有会话对象之后。
4. 没有对应会话的对象保持稳定顺序：先保留好友列表顺序，再保留社群列表顺序。
5. 点击好友目标时，先 `getOrCreateConversation(friend.id)`，再发送 `messageType: post` 和 `relatedId: post.id`。
6. 点击社群目标时，直接向社群聊天发送 `messageType: post` 和 `relatedId: post.id`。

## Architecture

新增一个分享目标解析层，放在 `lib/services/post_share_target_resolver.dart`。该层负责把好友、社群、会话缓存合并成统一的 `PostShareTarget` 列表，并提供加载方法供分享面板使用。

分享面板只负责 UI 和发送动作，不再承担缓存读取、对象混排和排序规则。

## Cache Keys

- 保留：`CacheKeys.friendList = 'friend:list'`
- 新增：`CacheKeys.communityMyList = 'community:my:list'`
- 复用：`CacheKeys.convFullList = 'conv:full:list'`

`CacheManifest` 增加社群列表条目，domain 使用 `community`，TTL 使用 300 秒，data shape 为 `List<Map>`。

## Data Flow

1. `PostShareTargetResolver.loadTargets()` 先读取：
   - `friend:list`
   - `community:my:list`
   - `conv:full:list`
2. 如果好友或社群缓存为空，则请求对应 API：
   - `FriendService().getFriends()`
   - `CommunityApiService().getMy()`
3. API 成功后写回缓存：
   - 好友写入 `friend:list`
   - 我的社群写入 `community:my:list`
4. Resolver 把好友和社群转换成统一 `PostShareTarget`。
5. Resolver 根据会话列表生成排序索引：
   - 私聊会话用 `conversation.otherUser.id` 匹配好友。
   - 社群会话用 `conversation.communityId` 匹配社群。
6. Resolver 输出已排序的目标列表给分享面板。

## Sorting Rules

排序 key：

1. `conversationIndex`，有会话时为会话列表下标，无会话时为空。
2. `fallbackIndex`，无会话时保持原始稳定顺序。

比较规则：

- 两个目标都有会话：`conversationIndex` 小的排前。
- 只有一个目标有会话：有会话的排前。
- 两个目标都没有会话：`fallbackIndex` 小的排前。

## UI

分享面板保持 modal bottom sheet 形式，标题仍为“发送帖子到聊天”。列表项从分组 `好友/社群` 改为统一列表：

- 好友：person 图标、好友显示名、subtitle 为“好友 · 发送帖子卡片”
- 社群：groups 图标、社群名称、subtitle 为“社群 · 发送帖子卡片”

本次不增加搜索框，避免扩大范围。搜索框可在后续基于 `PostShareTarget` 的统一模型添加。

## Testing

新增/更新 Flutter 契约测试覆盖：

- `CacheKeys.communityMyList` 存在。
- `CacheManifest` 注册 `community:my:list`。
- 分享目标解析器能把好友和社群混排。
- 混排顺序遵循会话列表顺序。
- 未出现在会话列表中的目标排到后面并保持稳定顺序。
- 分享面板使用 resolver，不再直接在 widget 中负责好友/社群 API 聚合排序。
