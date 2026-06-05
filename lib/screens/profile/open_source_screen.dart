import 'package:facebook_clone/config/app_theme.dart';
import 'package:flutter/material.dart';

class OpenSourceScreen extends StatelessWidget {
  const OpenSourceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '开源许可',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              context,
              '开源组件列表',
              '本应用使用了以下开源项目和库，在此向所有开源贡献者表示感谢。各开源组件的完整许可协议文本可在其各自的项目仓库中查看。',
            ),
            _buildDivider(),
            _buildTitle(context, 'Flutter'),
            _buildParagraph('许可证：BSD 3-Clause License'),
            _buildParagraph('Flutter 是 Google 的开源 UI 工具包，用于从单一代码库构建原生编译的多平台应用。本应用基于 Flutter 框架构建。'),

            _buildDivider(),
            _buildTitle(context, 'Dio'),
            _buildParagraph('许可证：MIT License'),
            _buildParagraph('Dio 是一个强大的 HTTP 网络请求库，支持拦截器、全局配置、FormData、请求取消、文件下载等功能。本应用使用 Dio 进行网络通信。'),

            _buildDivider(),
            _buildTitle(context, 'Provider'),
            _buildParagraph('许可证：MIT License'),
            _buildParagraph('Provider 是 Flutter 的状态管理库，提供了简单且高效的方式在 Widget 树中共享数据。本应用使用 Provider 进行状态管理。'),

            _buildDivider(),
            _buildTitle(context, 'CachedNetworkImage'),
            _buildParagraph('许可证：MIT License'),
            _buildParagraph('Cached Network Image 用于缓存网络图片并提供加载过程中的占位符。本应用使用它来优化图片加载体验。'),

            _buildDivider(),
            _buildTitle(context, 'share_plus'),
            _buildParagraph('许可证：BSD 3-Clause License'),
            _buildParagraph('share_plus 是 Flutter 的分享插件，支持通过系统分享菜单将文本、链接和文件分享到其他应用。本应用使用它来实现内容分享功能。'),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String subtitle, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildParagraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.only(top: 24),
      child: Divider(height: 1, color: AppColors.borderLight),
    );
  }
}
