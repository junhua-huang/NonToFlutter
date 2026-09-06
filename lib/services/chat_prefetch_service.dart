import 'dart:async';
import 'dart:convert';

import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/api/chat_service.dart';
import 'package:nonto/services/api/community_service.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/utils/date_utils.dart';

/// Opens the next chat without making the route wait for its history request.
///
/// The service only prepares recent-message caches. Joining a WebSocket room,
/// marking messages read, and creating the send queue remain screen-owned.
class ChatPrefetchService {
  static final ChatPrefetchService _instance = ChatPrefetchService._();
  factory ChatPrefetchService() => _instance;
  ChatPrefetchService._();

  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  Future<void> prefetchPrivateConversation(int conversationId) {
    return _prefetch(
      'private:$conversationId',
      () async {
        final tokenAtStart = ApiClient.token;
        final response = await ChatService()
            .getMessages(conversationId, perPage: 50)
            .timeout(const Duration(seconds: 12));
        if (tokenAtStart != ApiClient.token) return;
        if (!response.success || response.data == null) return;
        final messages = _extractMessages(response.data, latestFirst: true);
        if (messages.isEmpty) return;
        final hasMore = _extractHasMore(response.data, messages.length);
        final payload = <String, dynamic>{
          'messages': messages,
          'has_more': hasMore,
        };
        await DataLayer().write(CacheKeys.msgRecent(conversationId), payload);
        await DataLayer().write(CacheKeys.msgWarmup(conversationId), payload);
      },
    );
  }

  Future<void> prefetchCommunityChat(int communityId) {
    return _prefetch(
      'community:$communityId',
      () async {
        final tokenAtStart = ApiClient.token;
        final response = await CommunityApiService()
            .getChat(communityId, limit: 50)
            .timeout(const Duration(seconds: 12));
        if (tokenAtStart != ApiClient.token) return;
        if (!response.success || response.data is! Map) return;
        final data = Map<String, dynamic>.from(response.data as Map);
        final messages = _extractMessages(data['messages'], latestFirst: false);
        if (messages.isEmpty) return;
        await DataLayer().write(
          CacheKeys.communityChatRecent(communityId),
          messages,
        );
        final conversation = data['conversation'];
        final conversationId = conversation is Map
            ? int.tryParse(
                (conversation['conversation_id'] ?? conversation['id'])
                        ?.toString() ??
                    '')
            : null;
        if (conversationId != null) {
          final hasMore = _extractHasMore(data, messages.length);
          await DataLayer().write(CacheKeys.msgRecent(conversationId), {
            'messages': messages,
            'has_more': hasMore,
          });
        }
      },
    );
  }

  Future<void> _prefetch(String key, Future<void> Function() operation) {
    final existing = _inFlight[key];
    if (existing != null) return existing;

    late final Future<void> future;
    future = operation().catchError((_) {}).whenComplete(() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  bool _extractHasMore(dynamic raw, int messageCount) {
    dynamic value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return messageCount >= 50;
      }
    }
    if (value is Map) {
      final hasMore = value['has_more'] ?? value['hasMore'];
      if (hasMore is bool) return hasMore;
      if (value['has_more_before'] is bool) {
        return value['has_more_before'] == true;
      }
      if (value['next_page_url'] != null) return true;
    }
    return messageCount >= 50;
  }

  List<Map<String, dynamic>> _extractMessages(
    dynamic raw, {
    required bool latestFirst,
  }) {
    dynamic value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return const [];
      }
    }
    if (value is Map) {
      value = value['messages'] ?? value['items'] ?? value['data'] ?? [];
    }
    if (value is! List) return const [];
    final messages = value
        .whereType<Map>()
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
    messages.sort((a, b) {
      final compare = _messageTime(a).compareTo(_messageTime(b));
      return latestFirst ? -compare : compare;
    });
    return messages;
  }

  DateTime _messageTime(Map<String, dynamic> message) {
    return AppDateUtils.parseServerTime(message['created_at']?.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
}
