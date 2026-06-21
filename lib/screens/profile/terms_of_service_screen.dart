import 'package:nonto/config/app_theme.dart';
import 'package:flutter/material.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '用户协议',
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
              '最后更新日期：2026-05-26',
              '欢迎使用 nonto（以下简称"本应用"或"我们"）。请仔细阅读本用户协议（以下简称"本协议"），本协议构成您与我们之间具有法律约束力的协议。',
            ),
            _buildDivider(),
            _buildTitle(context, '一、接受条款'),
            _buildParagraph(
                '通过注册、访问或使用本应用，您确认您已阅读、理解并同意受本协议所有条款和条件的约束。如果您不同意本协议的任何部分，请勿注册或使用本应用。'),
            _buildParagraph(
                '您声明并保证：(a) 您已年满 13 周岁，或已达到您所在司法管辖区允许使用社交网络服务的最低年龄；(b) 您提供的注册信息真实、准确、最新且完整；(c) 您将维护并及时更新您的注册信息。'),
            _buildDivider(),
            _buildTitle(context, '二、账号管理'),
            _buildBoldParagraph(
                '2.1 账号创建', '您必须提供有效的电子邮箱地址并创建密码来注册账号。每个电子邮箱只能注册一个账号。'),
            _buildBoldParagraph('2.2 账号安全',
                '您对维护您的账号密码的机密性以及您账号下发生的所有活动负全部责任。如发现任何未经授权使用您账号的情况，应立即通知我们。'),
            _buildBoldParagraph('2.3 账号注销',
                '您有权随时注销您的账号。注销后，我们将按照隐私政策的规定处理您的数据。账号一旦注销，所有数据将被永久删除且不可恢复。'),
            _buildDivider(),
            _buildTitle(context, '三、用户行为规范'),
            _buildParagraph('您同意在使用本应用时不会从事以下行为：'),
            _buildBullet('发布或传播违法、有害、威胁、辱骂、骚扰、诽谤、粗俗、淫秽、侵犯他人隐私的内容'),
            _buildBullet('冒充他人或虚假陈述您与他人或实体的关系'),
            _buildBullet('发布垃圾邮件、广告或商业推广内容'),
            _buildBullet('上传包含病毒、恶意代码或任何可能损害本应用功能的内容'),
            _buildBullet('未经授权访问、篡改或干扰本应用的系统、服务器或网络'),
            _buildBullet('使用自动化方式（如机器人、爬虫）收集或提取数据'),
            _buildBullet('侵犯他人的知识产权、隐私权或其他合法权益'),
            _buildParagraph('我们保留审查、过滤、删除任何违反上述规定的用户内容的权利，恕不另行通知。'),
            _buildDivider(),
            _buildTitle(context, '四、知识产权'),
            _buildBoldParagraph('4.1 我们的权利',
                '本应用的名称、标识、设计、源代码、文本、图形和所有其他材料均受版权、商标和其他知识产权法律保护。未经我们明确书面许可，不得以任何方式使用。'),
            _buildBoldParagraph('4.2 用户内容许可',
                '通过在平台上发布内容，您授予我们非独占、全球性、免版税的许可，以便我们在运营和改进服务所需的范围内使用、复制、修改、展示和分发该内容。此许可的目的仅限于提供和改进我们的服务。'),
            _buildBoldParagraph(
                '4.3 第三方权利', '您声明并保证您发布的内容不侵犯任何第三方的知识产权、隐私权或其他权利。'),
            _buildDivider(),
            _buildTitle(context, '五、免责声明'),
            _buildParagraph(
                '在法律允许的最大范围内，本应用按"现状"和"可用"提供，不附带任何形式的明示或暗示保证，包括但不限于对适销性、特定用途适用性和非侵权的保证。'),
            _buildParagraph(
                '我们不保证：(a) 服务将不间断、安全或无错误；(b) 任何错误或缺陷将得到纠正；(c) 通过服务获得的内容准确或可靠。'),
            _buildDivider(),
            _buildTitle(context, '六、责任限制'),
            _buildParagraph(
                '在法律允许的最大范围内，我们不对因使用或无法使用本应用而产生的任何间接、附带、特殊、惩罚性或结果性损害承担责任，包括但不限于利润损失、数据丢失、商誉损失或业务中断，无论基于何种法律理论。'),
            _buildDivider(),
            _buildTitle(context, '七、服务变更和终止'),
            _buildParagraph(
                '我们保留随时修改、暂停或终止本服务（或其任何部分）的权利，无论是否事先通知。我们也保留出于任何原因（包括违反本协议）终止或暂停您的账号的权利。终止后，本协议中按其性质应在终止后继续有效的条款将持续有效。'),
            _buildDivider(),
            _buildTitle(context, '八、协议修改'),
            _buildParagraph(
                '我们可能不时修改本协议。重大修改将在生效前通过应用通知或电子邮件告知。如果您在修改生效后继续使用本应用，即表示您接受修改后的条款。如果您不同意修改后的条款，应停止使用本应用。'),
            _buildDivider(),
            _buildTitle(context, '九、适用法律和争议解决'),
            _buildParagraph(
                '本协议受中华人民共和国法律管辖并据其解释。因本协议引起的或与其相关的任何争议应首先通过友好协商解决。协商不成的，任何一方均有权向有管辖权的人民法院提起诉讼。'),
            _buildDivider(),
            _buildTitle(context, '十、联系我们'),
            _buildParagraph('如果您对本协议有任何疑问或意见，请通过以下方式联系我们：'),
            _buildBullet('电子邮箱：support@facebookclone.example.com'),
            _buildBullet('在线客服：应用内"帮助与反馈"页面'),
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
        style: TextStyle(
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
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: TextStyle(
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
        style: TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildBoldParagraph(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
            height: 1.6,
          ),
          children: [
            TextSpan(
              text: '$title ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: content),
          ],
        ),
      ),
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('  •  ',
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: EdgeInsets.only(top: 24),
      child: Divider(height: 1, color: AppColors.borderLight),
    );
  }
}
