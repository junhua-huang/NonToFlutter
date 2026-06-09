import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/topic.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/services/api/friend_service.dart';
import 'package:facebook_clone/services/api/search_service.dart';
import 'package:facebook_clone/services/api/topic_service.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:flutter/material.dart';
/// 底部弹出的 @好友 / #话题 选择器
/// 当用户输入 @ 或 # 时触发，支持搜索和推荐
class MentionTopicPicker extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;

  const MentionTopicPicker({
    super.key,
    required this.controller,
    this.focusNode,
  });

  /// Show a bottom sheet for picking a user to mention
  static void showMentions(BuildContext context, {required void Function(String username) onSelected}) {
    _showPickerSheet(context, isTopic: false, onSelected: onSelected);
  }

  /// Show a bottom sheet for picking a topic to hashtag
  static void showTopics(BuildContext context, {
    required void Function(String topicName) onSelected,
    void Function(String searchText)? onCancel,
  }) {
    _showPickerSheet(context, isTopic: true, onSelected: onSelected, onCancel: onCancel);
  }

  static void _showPickerSheet(
    BuildContext context, {
    required bool isTopic,
    required void Function(String) onSelected,
    void Function(String)? onCancel,
  }) {
    final searchController = TextEditingController();

    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) => _PickerSheetContent(
            isTopic: isTopic,
            scrollController: scrollController,
            searchController: searchController,
            onSelected: (value) {
              Navigator.pop(ctx, value);
              onSelected(value);
            },
          ),
        ),
      ),
    ).then((selectedValue) {
      if (selectedValue == null && onCancel != null) {
        // 弹窗被取消（没有选中结果），传递搜索框内容
        onCancel(searchController.text);
      }
      searchController.dispose();
    });
  }

  @override
  State<MentionTopicPicker> createState() => _MentionTopicPickerState();
}

class _MentionTopicPickerState extends State<MentionTopicPicker> {
  bool _isVisible = false;
  String _query = '';
  bool _isTopicMode = false; // true = #topic, false = @mention
  List<User> _users = [];
  List<Topic> _topics = [];
  bool _isLoading = false;

  // Track the position where @ or # was typed
  int _triggerPosition = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (!selection.isValid || selection.baseOffset <= 0) {
      _hide();
      return;
    }

    final cursorPos = selection.baseOffset;
    // Check if we're typing after @ or #
    if (cursorPos > 0 && cursorPos <= text.length) {
      final charBefore = text[cursorPos - 1];

      // Check if @ or # was just typed
      if (charBefore == '@' || charBefore == '#') {
        _triggerPosition = cursorPos - 1;
        _isTopicMode = charBefore == '#';
        _query = '';
        _loadSuggestions();
        _show();
        return;
      }

      // Check if we're continuing to type after @ or #
      if (_triggerPosition >= 0 && cursorPos > _triggerPosition) {
        final triggerChar = text[_triggerPosition];
        if (triggerChar == '@' || triggerChar == '#') {
          // Extract query between trigger and cursor
          _query = text.substring(_triggerPosition + 1, cursorPos);
          _isTopicMode = triggerChar == '#';
          _loadSuggestions();
          _show();
          return;
        }
      }
    }

    // If cursor moved before trigger position, hide
    if (_triggerPosition >= 0 && cursorPos <= _triggerPosition) {
      _hide();
      return;
    }

    // If space or newline after trigger, hide
    if (_triggerPosition >= 0 && cursorPos > _triggerPosition) {
      final typedAfter = text.substring(_triggerPosition + 1, cursorPos);
      if (typedAfter.contains(' ') || typedAfter.contains('\n')) {
        _hide();
        return;
      }
    }
  }

  void _show() {
    if (!_isVisible) {
      setState(() => _isVisible = true);
    }
  }

  void _hide() {
    if (_isVisible) {
      setState(() {
        _isVisible = false;
        _triggerPosition = -1;
        _query = '';
        _users = [];
        _topics = [];
      });
    }
  }

  Future<void> _loadSuggestions() async {
    setState(() => _isLoading = true);
    try {
      if (_isTopicMode) {
        // Load topic suggestions
        if (_query.isEmpty) {
          // Show trending topics
          final resp = await TopicService().getTrending(limit: 8);
          if (resp.success && resp.data != null) {
            final data = resp.data;
            List topicList = [];
            if (data is List) { topicList = data; }
            else if (data is Map) { topicList = data['topics'] ?? data['items'] ?? []; }
            setState(() {
              _topics = topicList.map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList();
            });
          }
        } else {
          // Search topics
          final resp = await TopicService().getTopics(q: _query, perPage: 8);
          if (resp.success && resp.data != null) {
            final data = resp.data;
            List topicList = [];
            if (data is List) { topicList = data; }
            else if (data is Map) { topicList = data['topics'] ?? data['items'] ?? []; }
            setState(() {
              _topics = topicList.map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList();
            });
          }
        }
      } else {
        // Load user/mention suggestions
        if (_query.isEmpty) {
          // Show friends
          final resp = await FriendService().getFriends();
          if (resp.success && resp.data != null) {
            final data = resp.data;
            List userList = [];
            if (data is List) { userList = data; }
            else if (data is Map) { userList = data['friends'] ?? data['users'] ?? data['items'] ?? []; }
            setState(() {
              _users = userList.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
            });
          }
        } else {
          // Search users
          final resp = await SearchService().suggestUsers(_query, limit: 8);
          if (resp.success && resp.data != null) {
            final data = resp.data;
            List userList = [];
            if (data is List) { userList = data; }
            else if (data is Map) { userList = data['users'] ?? data['items'] ?? []; }
            setState(() {
              _users = userList.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('MentionTopicPicker load error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onSelect(String value) {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;

    if (_triggerPosition >= 0 && _triggerPosition < cursorPos) {
      // Replace the text from trigger position to cursor with the selected value
      final before = text.substring(0, _triggerPosition);
      final after = text.substring(cursorPos);
      final newText = '$before$value $after';
      widget.controller.text = newText;
      // Move cursor after the inserted value + space
      final newCursorPos = _triggerPosition + value.length + 1;
      widget.controller.selection = TextSelection.collapsed(offset: newCursorPos);
    }
    _hide();
    widget.focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      constraints: const BoxConstraints(maxHeight: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderLight)),
            ),
            child: Row(
              children: [
                Icon(
                  _isTopicMode ? Icons.tag : Icons.alternate_email,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  _isTopicMode
                      ? (_query.isEmpty ? '热门话题' : '搜索话题')
                      : (_query.isEmpty ? '推荐好友' : '搜索用户'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _hide,
                  child: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _isTopicMode
                    ? _buildTopicList()
                    : _buildUserList(),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    if (_users.isEmpty) {
      return const Center(
        child: Text('没有找到相关用户', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      );
    }
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (_, i) {
        final user = _users[i];
        return InkWell(
          onTap: () => _onSelect('@${user.username}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ImageUtils.buildAvatar(user, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName ?? user.username,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                      Text('@${user.username}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopicList() {
    if (_topics.isEmpty) {
      return const Center(
        child: Text('没有找到相关话题', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      );
    }
    return ListView.builder(
      itemCount: _topics.length,
      itemBuilder: (_, i) {
        final topic = _topics[i];
        return InkWell(
          onTap: () => _onSelect('#${topic.name}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tag, size: 16, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('#${topic.name}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                      if (topic.postCount > 0)
                        Text('${topic.postCount} 条帖子',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bottom sheet content for manual @/# picker
class _PickerSheetContent extends StatefulWidget {
  final bool isTopic;
  final ScrollController scrollController;
  final TextEditingController searchController;
  final void Function(String) onSelected;

  const _PickerSheetContent({
    required this.isTopic,
    required this.scrollController,
    required this.searchController,
    required this.onSelected,
  });

  @override
  State<_PickerSheetContent> createState() => _PickerSheetContentState();
}

class _PickerSheetContentState extends State<_PickerSheetContent> {
  late final TextEditingController _searchController;
  List<User> _users = [];
  List<Topic> _topics = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController = widget.searchController;
    _loadRecommendations();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    // 由于 searchController 是从外部传入的，需要在 _showPickerSheet 中 dispose
    super.dispose();
  }

  Future<void> _loadRecommendations() async {
    setState(() => _isLoading = true);
    try {
      if (widget.isTopic) {
        final resp = await TopicService().getTrending(limit: 10);
        if (resp.success && resp.data != null) {
          final data = resp.data as Map<String, dynamic>;
          final list = data['topics'] as List? ?? [];
          setState(() => _topics = list.map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList());
        }
      } else {
        final resp = await FriendService().getFriendRecommendations(limit: 10);
        if (resp.success && resp.data != null) {
          final data = resp.data;
          List userList = [];
          if (data is List) { userList = data; }
          else if (data is Map) { userList = data['users'] ?? data['items'] ?? []; }
          setState(() => _users = userList.map((e) => User.fromJson(e as Map<String, dynamic>)).toList());
        }
      }
    } catch (e) {
      debugPrint('Picker load error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _onSearchChanged() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _loadRecommendations();
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (widget.isTopic) {
        final resp = await SearchService().searchTopics(query);
        if (resp.success && resp.data != null) {
          final list = resp.data['topics'] ?? resp.data['results'] ?? resp.data;
          if (list is List) {
            setState(() => _topics = list.map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList());
          }
        }
      } else {
        final resp = await SearchService().searchUsers(query);
        if (resp.success && resp.data != null) {
          final list = resp.data['users'] ?? resp.data['results'] ?? resp.data;
          if (list is List) {
            setState(() => _users = list.map((e) => User.fromJson(e as Map<String, dynamic>)).toList());
          }
        }
      }
    } catch (e) {
      debugPrint('Picker search error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Drag handle
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          width: 36,
          height: 4,
          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(widget.isTopic ? Icons.tag : Icons.alternate_email,
                size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(widget.isTopic ? '选择话题' : '选择好友',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
        ),
        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.isTopic ? '搜索话题...' : '搜索好友...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        const Divider(height: 1),
        // List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ListView.builder(
                  controller: widget.scrollController,
                  itemCount: widget.isTopic ? _topics.length : _users.length,
                  itemBuilder: (context, index) {
                    if (widget.isTopic) {
                      final topic = _topics[index];
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.tag, size: 18, color: AppColors.primary),
                        ),
                        title: Text('#${topic.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: topic.postCount > 0 ? Text('${topic.postCount} 条帖子') : null,
                        onTap: () => widget.onSelected(topic.name),
                      );
                    } else {
                      final user = _users[index];
                      return ListTile(
                        leading: ImageUtils.buildAvatar(user, radius: 20),
                        title: Text(user.displayName ?? user.username, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('@${user.username}'),
                        onTap: () => widget.onSelected(user.username),
                      );
                    }
                  },
                ),
        ),
      ],
    );
  }
}

