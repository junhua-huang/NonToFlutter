import 'package:facebook_clone/config/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
/// 解析文本中的话题(#xxx)和@提及(@xxx)，高亮显示并支持点击
class RichTextContent extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final void Function(String topic)? onTopicTap;
  final void Function(String username)? onMentionTap;

  const RichTextContent({
    super.key,
    required this.text,
    this.style,
    this.highlightStyle,
    this.maxLines,
    this.overflow,
    this.onTopicTap,
    this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = style ?? const TextStyle(fontSize: 15, height: 1.45, color: AppColors.textPrimary);
    final linkStyle = highlightStyle ?? const TextStyle(fontSize: 15, height: 1.45, color: AppColors.primary, fontWeight: FontWeight.w500);

    final spans = _parseText(text, defaultStyle, linkStyle);

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }

  List<TextSpan> _parseText(String text, TextStyle defaultStyle, TextStyle linkStyle) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'([#@][\w\u4e00-\u9fa5]+)');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      // Add plain text before match
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start), style: defaultStyle));
      }

      final matched = match.group(0)!;
      if (matched.startsWith('#')) {
        final topic = matched.substring(1);
        spans.add(TextSpan(
          text: matched,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (onTopicTap != null) onTopicTap!(topic);
            },
        ));
      } else if (matched.startsWith('@')) {
        final username = matched.substring(1);
        spans.add(TextSpan(
          text: matched,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (onMentionTap != null) onMentionTap!(username);
            },
        ));
      }

      lastEnd = match.end;
    }

    // Add remaining plain text
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: defaultStyle));
    }

    return spans;
  }
}
