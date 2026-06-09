import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Resolve shimmer colors based on theme brightness
class _ShimmerColors {
  final Color base;
  final Color highlight;

  const _ShimmerColors(this.base, this.highlight);

  factory _ShimmerColors.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _ShimmerColors(
      dark ? const Color(0xFF2A2D31) : const Color(0xFFE8ECEE),
      dark ? const Color(0xFF3A3E43) : const Color(0xFFF9FAFB),
    );
  }
}

/// Feed/post list skeleton shimmer
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = _ShimmerColors.of(context);
    return Shimmer.fromColors(
      baseColor: c.base,
      highlightColor: c.highlight,
      period: const Duration(milliseconds: 1200),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: 4,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCCCCCC),
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Box(width: 100, height: 14),
                        const SizedBox(height: 6),
                        _Box(width: 70, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _Box(height: 14, width: double.infinity),
              const SizedBox(height: 6),
              _Box(height: 14, width: 260),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: const _Box(height: 200, width: double.infinity),
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  _Box(width: 60, height: 12),
                  Spacer(),
                  _Box(width: 60, height: 12),
                  Spacer(),
                  _Box(width: 60, height: 12),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// Conversation list skeleton
class ConversationSkeleton extends StatelessWidget {
  const ConversationSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = _ShimmerColors.of(context);
    return Shimmer.fromColors(
      baseColor: c.base,
      highlightColor: c.highlight,
      period: const Duration(milliseconds: 1200),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: 6,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFCCCCCC),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Box(width: 140, height: 15),
                    const SizedBox(height: 6),
                    const _Box(width: 220, height: 13),
                  ],
                ),
              ),
              const _Box(width: 50, height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Notification skeleton
class NotificationSkeleton extends StatelessWidget {
  const NotificationSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = _ShimmerColors.of(context);
    return Shimmer.fromColors(
      baseColor: c.base,
      highlightColor: c.highlight,
      period: const Duration(milliseconds: 1200),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: 5,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFCCCCCC),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Box(width: 200, height: 14),
                    const SizedBox(height: 8),
                    const _Box(height: 50, width: double.infinity),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  final double width;
  final double height;
  const _Box({this.width = double.infinity, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFCCCCCC),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

/// User/friend list skeleton (avatar + 2 lines)
class FriendSkeleton extends StatelessWidget {
  const FriendSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = _ShimmerColors.of(context);
    return Shimmer.fromColors(
      baseColor: c.base,
      highlightColor: c.highlight,
      period: const Duration(milliseconds: 1200),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: 8,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFCCCCCC),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Box(width: 120, height: 15),
                    const SizedBox(height: 6),
                    const _Box(width: 180, height: 13),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
