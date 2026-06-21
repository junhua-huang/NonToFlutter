import 'package:flutter/foundation.dart';

/// 全局聊天室状态持有者。
///
/// `currentChatRoomConvId` 记录当前正在打开的会话 ID（字符串形式）。
/// 用于：
///   - 未读消息统计：当前打开的会话不应产生未读红点（见 chat_notifiers.dart）。
///   - WS 消息路由：当前会话的消息直接进 MessagesNotifier，不重复计入未读。
///
/// 之所以独立成文件而非放在 MessagesTab 里，是为了打破循环依赖：
/// chat_notifiers（被 messages_tab 导入）需要读取这个值，
/// 而 messages_tab 又导入 chat_notifiers，若值定义在 messages_tab 里会形成环。
class ChatRoomState {
  ChatRoomState._();

  /// 当前正在打开的会话 ID（字符串）；null 表示没有打开任何聊天室。
  static String? currentChatRoomConvId;

  /// 当前会话 ID 是否等于 [convId]（统一字符串比较，避免 int/str 类型不一致）。
  static bool isOpen(int convId) {
    final cur = currentChatRoomConvId;
    if (cur == null) return false;
    return cur == convId.toString();
  }

  /// 调试：记录进入/离开聊天室。
  static void setConversation(int? convId) {
    currentChatRoomConvId = convId?.toString();
    if (kDebugMode) {
      debugPrint('[ChatRoomState] currentConvId=$currentChatRoomConvId');
    }
  }
}
