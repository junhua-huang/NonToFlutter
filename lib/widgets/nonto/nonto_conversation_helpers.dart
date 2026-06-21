import 'package:nonto/models/conversation.dart';

List<Conversation> filterNontoConversations(
  List<Conversation> conversations,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return conversations;

  return conversations.where((conversation) {
    final other = conversation.otherUser;
    final fields = <String?>[
      other?.displayName,
      other?.username,
      conversation.communityName,
      conversation.lastMessage?.content,
    ];

    return fields.any(
      (field) => field != null && field.toLowerCase().contains(normalizedQuery),
    );
  }).toList(growable: false);
}

String nontoConversationPreview(Conversation conversation) {
  final lastMessage = conversation.lastMessage;
  if (lastMessage?.isRecalled == true) return '消息已撤回';

  final content = lastMessage?.content?.trim() ?? '';
  if (conversation.isCommunity && content.isEmpty) return '社群群聊';
  if (content.isEmpty) return '暂无消息';

  return content;
}
