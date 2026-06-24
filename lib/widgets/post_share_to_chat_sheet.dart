import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nonto/models/community.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/services/api/chat_service.dart';
import 'package:nonto/services/api/community_service.dart';

class PostShareToChatSheet extends StatefulWidget {
  final Post post;

  const PostShareToChatSheet({super.key, required this.post});

  static Future<void> show(BuildContext context, {required Post post}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PostShareToChatSheet(post: post),
    );
  }

  @override
  State<PostShareToChatSheet> createState() => _PostShareToChatSheetState();
}

class _PostShareToChatSheetState extends State<PostShareToChatSheet> {
  late final Future<_ShareTargets> _targetsFuture = _loadTargets();
  bool _sending = false;

  Future<_ShareTargets> _loadTargets() async {
    final responses = await Future.wait([
      ChatService().getConversations(page: 1, perPage: 30),
      CommunityApiService().getMy(),
    ]);

    return _ShareTargets(
      conversations: _parseConversations(responses[0].data),
      communities: _parseCommunities(responses[1].data),
    );
  }

  List<Conversation> _parseConversations(dynamic data) {
    final items = _extractItems(data, const [
      'conversations',
      'sessions',
      'items',
      'data',
    ]);
    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map(Conversation.fromJson)
        .where((conversation) => !conversation.isCommunity)
        .toList();
  }

  List<Community> _parseCommunities(dynamic data) {
    final items = _extractItems(data, const [
      'communities',
      'items',
      'data',
    ]);
    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map(Community.fromJson)
        .where((community) => community.isMember)
        .toList();
  }

  List<dynamic> _extractItems(dynamic data, List<String> keys) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in keys) {
        final value = data[key];
        if (value is List) return value;
        if (value is Map) {
          final nested = _extractItems(value, keys);
          if (nested.isNotEmpty) return nested;
        }
      }
    }
    return const [];
  }

  Future<void> _sendToConversation(Conversation conversation) async {
    final post = widget.post;
    await _send(() {
      return ChatService().sendMessage(
        conversation.id,
        post.content ?? '',
        messageType: 'post',
        relatedId: post.id,
      );
    });
  }

  Future<void> _sendToCommunity(Community community) async {
    final post = widget.post;
    await _send(() {
      return CommunityApiService().sendMessage(
        community.id,
        content: post.content ?? '',
        messageType: 'post',
        relatedId: post.id,
      );
    });
  }

  Future<void> _send(Future<dynamic> Function() action) async {
    if (_sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await action();
      if (!mounted) return;
      Navigator.of(context).pop();
      final success = response?.success == true;
      final message = success ? '已发送帖子' : (response?.message ?? '发送失败');
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('发送失败，请重试')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: FutureBuilder<_ShareTargets>(
          future: _targetsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return SizedBox(
                height: 180,
                child: Center(
                  child: Text(
                    '加载会话失败',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              );
            }

            final targets = snapshot.data ?? const _ShareTargets();
            final hasTargets = targets.conversations.isNotEmpty || targets.communities.isNotEmpty;
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '发送帖子到聊天',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  if (!hasTargets)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: Text('暂无可发送的聊天或社群')),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (targets.conversations.isNotEmpty) ...[
                            const _SectionHeader('私聊'),
                            for (final conversation in targets.conversations)
                              ListTile(
                                enabled: !_sending,
                                contentPadding: EdgeInsets.zero,
                                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                                title: Text(conversation.otherUser?.displayName ?? conversation.otherUser?.username ?? '用户'),
                                subtitle: const Text('发送帖子卡片'),
                                onTap: () => _sendToConversation(conversation),
                              ),
                          ],
                          if (targets.communities.isNotEmpty) ...[
                            const _SectionHeader('社群'),
                            for (final community in targets.communities)
                              ListTile(
                                enabled: !_sending,
                                contentPadding: EdgeInsets.zero,
                                leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
                                title: Text(community.name),
                                subtitle: const Text('发送帖子卡片'),
                                onTap: () => _sendToCommunity(community),
                              ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ShareTargets {
  final List<Conversation> conversations;
  final List<Community> communities;

  const _ShareTargets({
    this.conversations = const [],
    this.communities = const [],
  });
}
