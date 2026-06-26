import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/services/api/chat_service.dart';
import 'package:nonto/services/api/community_service.dart';
import 'package:nonto/services/post_share_target_resolver.dart';

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
  late final Future<List<PostShareTarget>> _targetsFuture =
      PostShareTargetResolver().loadTargets();
  bool _sending = false;

  Future<void> _sendToFriend(PostShareTarget target) async {
    final post = widget.post;
    await _send(() async {
      final convResp =
          await ChatService().getOrCreateConversation(target.friend!.id);
      if (convResp.success != true) return convResp;
      final data = convResp.data;
      final conversation = data is Map ? (data['conversation'] ?? data) : null;
      final conversationId = conversation is Map
          ? int.tryParse(conversation['id']?.toString() ?? '')
          : null;
      if (conversationId == null || conversationId <= 0) {
        throw StateError('conversation_id_missing');
      }
      return ChatService().sendMessage(
        conversationId,
        post.content ?? '',
        messageType: 'post',
        relatedId: post.id,
      );
    });
  }

  Future<void> _sendToCommunity(PostShareTarget target) async {
    final post = widget.post;
    await _send(() {
      return CommunityApiService().sendMessage(
        target.community!.id,
        content: post.content ?? '',
        messageType: 'post',
        relatedId: post.id,
      );
    });
  }

  Future<void> _sendToTarget(PostShareTarget target) {
    switch (target.type) {
      case PostShareTargetType.friend:
        return _sendToFriend(target);
      case PostShareTargetType.community:
        return _sendToCommunity(target);
    }
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
        child: FutureBuilder<List<PostShareTarget>>(
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
                    '加载分享对象失败',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              );
            }

            final targets = snapshot.data ?? const <PostShareTarget>[];
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
                  if (targets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: Text('暂无可发送的聊天或社群')),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: targets.length,
                        itemBuilder: (context, index) {
                          final target = targets[index];
                          return ListTile(
                            enabled: !_sending,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              child: Icon(
                                target.type == PostShareTargetType.friend
                                    ? Icons.person_outline
                                    : Icons.groups_outlined,
                              ),
                            ),
                            title: Text(target.title),
                            subtitle: Text(target.subtitle),
                            onTap: () => _sendToTarget(target),
                          );
                        },
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
