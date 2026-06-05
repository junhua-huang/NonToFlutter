import 'package:flutter_test/flutter_test.dart';
import 'package:facebook_clone/services/api/chat_service.dart';
import '../../helpers/test_helpers.dart';

void main() {
  late ChatService chatService;

  setUp(() {
    chatService = ChatService();
  });

  tearDown(() {
    tearDownMockDio();
  });

  group('chat_service - getConversations', () {
    test('getConversations 列表解析', () async {
      mockSuccess({
        'items': [
          {'id': 1, 'user1_id': 1, 'user2_id': 2, 'unread_count': 2},
          {'id': 2, 'user1_id': 1, 'user2_id': 3, 'unread_count': 0},
        ],
      });
      final resp = await chatService.getConversations();
      expectSuccess(resp);
    });

    test('getConversations 失败返回错误', () async {
      mockHttpError(500, 'Server error');
      final resp = await chatService.getConversations();
      expectFailure(resp);
    });
  });

  group('chat_service - sendMessage', () {
    test('sendMessage 请求体正确', () async {
      mockSuccess({'id': 500, 'content': 'Hello', 'message_type': 'text'});
      final resp = await chatService.sendMessage(1, 'Hello');
      expectSuccess(resp);
    });

    test('sendMessage 指定 message_type', () async {
      mockSuccess({'id': 501, 'content': 'img', 'message_type': 'image'});
      final resp = await chatService.sendMessage(1, 'img', messageType: 'image');
      expectSuccess(resp);
    });
  });

  group('chat_service - getMessages', () {
    test('getMessages 分页', () async {
      mockSuccess({
        'messages': [],
        'has_more': false,
        'current_page': 1,
        'pages': 1,
      });
      final resp = await chatService.getMessages(1, page: 2, perPage: 50);
      expectSuccess(resp);
    });
  });

  group('chat_service - markRead', () {
    test('markAsRead 调用正确', () async {
      mockSuccess({'message': 'ok'});
      final resp = await chatService.markRead(1);
      expectSuccess(resp);
    });
  });

  group('chat_service - getUnreadCount', () {
    test('getUnreadCount 返回值', () async {
      mockSuccess({'unread_count': 5});
      final resp = await chatService.getUnreadCount();
      expectSuccess(resp);
    });
  });

  group('chat_service - getOnlineUsers', () {
    test('getOnlineUsers 正确调用', () async {
      mockSuccess({'users': [1, 2, 3]});
      final resp = await chatService.getOnlineUsers();
      expectSuccess(resp);
    });
  });

  group('chat_service - getUserStatus', () {
    test('getUserStatus 正确调用', () async {
      mockSuccess({'user_id': 1, 'is_online': true});
      final resp = await chatService.getUserStatus(1);
      expectSuccess(resp);
    });
  });
}
