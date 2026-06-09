# ReliableWebSocket

基于 Drift 的强壮 WebSocket 模块 —— 消息确认、有序交付、发件箱持久化、自动重连、与业务解耦。

## 特性

| 能力 | 说明 |
|------|------|
| 🔁 消息确认与重传 | 发件箱持久化，超时 15s，最多重试 3 次 |
| 📊 有序交付 | 服务端序号 + 乱序缓冲 + 自动补发 |
| 🔌 自动重连 | 指数退避（1s→2s→4s→8s→60s），无限重试 |
| 💾 离线恢复 | 重连后自动补发离线消息 + 重发 pending 消息 |
| ❤️ 心跳保活 | 30s ping，60s 无响应判定断线 |
| 🧩 业务解耦 | 不依赖任何状态管理，通过回调注入 |
| 🌐 跨平台 | Android / iOS / Web / Windows / macOS / Linux |

## 安装

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  reliable_websocket:
    git:
      url: https://github.com/junhua-huang/ReliableWebSocket.git
```

或本地路径引用：

```yaml
dependencies:
  reliable_websocket:
    path: ../ReliableWebSocket
```

## 快速开始

```dart
import 'package:reliable_websocket/reliable_websocket.dart';

final client = ReliableWebSocketClient(
  url: 'wss://api.example.com/ws',
  getToken: () async => 'your-jwt-token',
  onMessage: (payload, seq) {
    print('收到消息 seq=$seq: $payload');
  },
  onConnectionStateChange: (state) {
    print('连接状态: $state');
  },
  onMessageSent: (clientMsgId) {
    print('消息已发送: $clientMsgId');
  },
  onMessageFailed: (clientMsgId, error) {
    print('发送失败: $clientMsgId - $error');
  },
  onAuthFailed: (error) {
    print('认证失败: $error');
  },
);

// 连接
await client.connect();

// 发送消息（返回 clientMsgId 用于追踪）
final msgId = await client.send({'type': 'chat', 'text': 'hello world'});

// 检查连接状态
print(client.isConnected); // true
print(client.lastReceivedSeq); // 当前已交付的最大序号

// 断开
await client.disconnect();
```

## 可配置项

```dart
ReliableWebSocketClient(
  // 必填
  url: 'wss://...',
  getToken: () async => token,
  onMessage: (payload, seq) {},
  onConnectionStateChange: (state) {},

  // 可选回调
  onMessageSent: (id) {},           // 消息确认送达
  onMessageFailed: (id, err) {},    // 消息最终失败
  onAuthFailed: (err) {},           // 认证失败

  // 超时控制（以下均为默认值）
  connectTimeout: Duration(seconds: 15),
  ackTimeout: Duration(seconds: 15),
  heartbeatInterval: Duration(seconds: 30),
  maxPingMissCount: 2,              // 心跳连续丢失判定断线
  maxRetries: 3,                    // 消息最大重试次数
  maxOutboxSize: 1000,             // 发件箱最大容量

  // 同步恢复
  syncTimeout: Duration(seconds: 30),
  syncMaxRetries: 3,
);
```

## 应用前后台处理

```dart
// App 回到前台
client.onAppForeground();

// App 进入后台（可选断开连接）
client.onAppBackground(disconnect: true);
```

## 协议约定

服务端需实现以下协议（全部 JSON 格式）：

### 客户端 → 服务端

| type | 说明 | 字段 |
|------|------|------|
| `auth` | 认证 | `token` |
| `send` | 发送消息 | `clientMsgId`, `payload` |
| `sync` | 请求补发 | `lastReceivedSeq` |
| `ping` | 心跳 | 无 |

### 服务端 → 客户端

| type | 说明 | 字段 |
|------|------|------|
| `auth_result` | 认证结果 | `success`, `error`(可选) |
| `ack` | 消息确认 | `clientMsgId`, `serverSeq` |
| `message` | 推送消息 | `seq`, `payload` |
| `sync_result` | 补发结果 | `messages` |
| `pong` | 心跳响应 | 无 |

**重要约定：**
- 服务端为每个消息分配严格递增的 `seq`
- 相同 `clientMsgId` 的 send 需幂等处理
- `sync_result` 消息超过 200 条需分页

## 测试

```bash
# 协议层
dart test test/protocol/

# 数据库 + 发件箱
flutter test test/database/

# 接收器组件
flutter test test/component/

# 端到端集成测试
flutter test test/integration/
```

## 许可证

MIT
