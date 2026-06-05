import 'package:facebook_clone/config/app_theme.dart';
import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '隐私政策',
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
              '感谢您使用 nonto（以下简称"我们"或"本应用"）。我们深知个人信息对您的重要性，并将按法律法规要求，采取相应安全保护措施，尽力保护您的个人信息安全可控。',
            ),
            _buildDivider(),
            _buildTitle(context, '一、信息收集'),
            _buildParagraph(
              '在您使用本应用的过程中，我们可能会收集以下类型的信息：',
            ),
            _buildBoldParagraph('1.1 注册信息', '当您注册账号时，我们需要收集您的用户名、电子邮箱地址。这些信息是提供账户创建和身份识别服务所必需的。'),
            _buildBoldParagraph('1.2 用户生成内容', '您在平台上发布的帖子、评论、点赞、分享等内容，以及您上传的图片、视频等媒体文件。我们收集这些信息以提供社交互动功能。'),
            _buildBoldParagraph('1.3 设备信息', '我们可能自动收集您所使用的设备型号、操作系统版本、唯一设备标识符、IP 地址、浏览器类型、移动网络信息等，用于保障服务的安全性和稳定性。'),
            _buildBoldParagraph('1.4 使用日志', '当您访问或使用本应用时，我们会自动记录您的访问时间、浏览记录、搜索记录、交互行为等日志信息。'),
            _buildBoldParagraph('1.5 Cookie 和类似技术', '我们使用 Cookie 和类似跟踪技术来提升用户体验、分析使用趋势和管理网站。您可以通过浏览器设置管理 Cookie 偏好。'),

            _buildDivider(),
            _buildTitle(context, '二、信息使用'),
            _buildParagraph('我们收集的信息将用于以下目的：'),
            _buildBullet('提供、维护和改进我们的社交服务'),
            _buildBullet('向您发送与服务相关的通知（如验证邮件、安全提醒）'),
            _buildBullet('处理您的请求、反馈和投诉'),
            _buildBullet('分析和研究用户行为以改善产品体验'),
            _buildBullet('检测、防止和解决欺诈、安全或技术问题'),
            _buildBullet('遵守适用的法律法规和执法要求'),
            _buildBullet('在匿名化和去标识化后用于统计和研究目的'),

            _buildDivider(),
            _buildTitle(context, '三、信息存储'),
            _buildParagraph('我们采用以下措施保护您的信息：'),
            _buildBoldParagraph('3.1 数据加密', '所有用户数据在传输过程中使用 TLS/SSL 加密协议，存储时使用 AES-256 加密。密码均经哈希加盐处理后存储，我们无法获取您的明文密码。'),
            _buildBoldParagraph('3.2 存储位置', '您的数据存储在位于中华人民共和国境内的服务器上。我们严格遵守《中华人民共和国个人信息保护法》关于数据本地化的要求。'),
            _buildBoldParagraph('3.3 保留期限', '我们仅在实现本政策所述目的所必需的最短时间内保留您的个人信息，除非法律要求或允许更长的保留期限。当您的账号被注销后，我们将在 30 天内删除或匿名化处理您的个人信息。'),

            _buildDivider(),
            _buildTitle(context, '四、用户权利（GDPR 与中国个人信息保护法）'),
            _buildParagraph('根据 GDPR（《通用数据保护条例》）和《中华人民共和国个人信息保护法》，您享有以下权利：'),
            _buildBoldParagraph('4.1 访问权', '您有权请求访问我们所持有的关于您的个人信息副本。您可以在应用"设置→隐私设置"中查看大部分个人信息。'),
            _buildBoldParagraph('4.2 更正权', '如果您的个人信息不准确或不完整，您有权要求更正。您可以在"编辑资料"页面自行修改基本信息。'),
            _buildBoldParagraph('4.3 删除权（被遗忘权）', '您有权在一定情况下要求删除您的个人数据。您可以通过"设置→账号注销"功能来行使此权利。一旦确认注销，我们将从服务器中永久删除您的账号和相关数据。该操作不可撤销。'),
            _buildBoldParagraph('4.4 数据可携带权', '您有权以结构化、通用和机器可读的格式接收您提供给我们的个人数据，并有权将这些数据转移给其他数据控制者。如需导出数据，请联系我们的支持团队。'),
            _buildBoldParagraph('4.5 反对权', '您有权基于与您特定情况相关的理由，在任何时候反对我们处理您的个人数据。您也可以随时反对将您的个人数据用于直接营销目的。'),
            _buildBoldParagraph('4.6 限制处理权', '在特定情况下，您有权要求限制对您个人数据的处理。例如当您质疑数据准确性时，可要求限制处理以便我们核实。'),
            _buildBoldParagraph('4.7 撤回同意权', '您有权随时撤回您对我们处理个人信息的同意。撤回同意不影响撤回前基于同意进行的合法处理。'),

            _buildDivider(),
            _buildTitle(context, '五、Cookie 政策'),
            _buildParagraph('我们使用 Cookie 和类似技术来：'),
            _buildBullet('识别您的登录身份和会话状态'),
            _buildBullet('记住您的偏好设置（如语言、主题）'),
            _buildBullet('分析应用使用情况以优化服务'),
            _buildBullet('保障账户和服务的安全性'),
            _buildParagraph('您可以通过浏览器设置或应用偏好来管理或禁用 Cookie，但请注意，这可能会影响部分功能的正常使用。'),

            _buildDivider(),
            _buildTitle(context, '六、第三方服务'),
            _buildParagraph('我们可能在以下情况下与第三方共享您的信息：'),
            _buildBoldParagraph('6.1 服务提供商', '我们可能与提供支付处理、数据分析、邮件发送、托管服务等支持的第三方公司共享必要的信息。这些提供商仅在为我们提供服务的目的下访问您的数据，并负有保密义务。'),
            _buildBoldParagraph('6.2 法律要求', '在法律、法规、法律程序或政府要求下，我们可能披露您的个人信息。'),
            _buildBoldParagraph('6.3 业务转让', '在合并、收购或出售全部或部分资产的情况下，您的信息可能作为资产的一部分被转移。您将通过邮件和/或我们网站上的显著通知获知所有权变更。'),
            _buildBoldParagraph('6.4 匿名数据', '我们可能与合作伙伴共享去标识化或聚合的非个人身份信息（如使用趋势统计）。'),

            _buildDivider(),
            _buildTitle(context, '七、儿童隐私（COPPA 合规声明）'),
            _buildParagraph('本应用遵循美国《儿童在线隐私保护法》（COPPA）和《中华人民共和国未成年人保护法》的相关规定：'),
            _buildBullet('我们的服务不面向 13 岁以下的儿童。我们不会故意收集 13 岁以下儿童的个人信息。'),
            _buildBullet('如果您是家长或监护人，并发现您的孩子未经您同意向我们提供了个人信息，请立即联系我们，我们将采取措施删除此类信息。'),
            _buildBullet('未满 14 周岁的未成年人使用本服务须在其监护人的知情和同意下进行。'),

            _buildDivider(),
            _buildTitle(context, '八、数据安全'),
            _buildParagraph('我们实施适当的技术和组织安全措施来保护您的个人信息免受未经授权的访问、更改、披露或销毁：'),
            _buildBullet('使用加密技术保护数据传输和存储'),
            _buildBullet('实施访问控制机制，限制对个人信息的访问权限'),
            _buildBullet('定期进行安全评估和渗透测试'),
            _buildBullet('对员工进行数据安全和隐私保护培训'),
            _buildParagraph('尽管我们采取了上述措施，但请注意没有任何安全措施是百分之百安全的。如果发生数据泄露事件，我们将根据适用法律的要求通知您和相关部门。'),

            _buildDivider(),
            _buildTitle(context, '九、隐私政策更新'),
            _buildParagraph('我们可能会不时更新本隐私政策。当我们进行重大更改时，我们将通过应用内通知和/或电子邮件等方式通知您，并在本页顶部更新"最后更新日期"。我们建议您定期查看本隐私政策以了解最新变化。继续使用本服务即表示您同意更新后的隐私政策。'),

            _buildDivider(),
            _buildTitle(context, '十、联系我们'),
            _buildParagraph('如果您对本隐私政策有任何疑问、意见或投诉，或希望行使您的数据权利，请通过以下方式联系我们：'),
            _buildBullet('电子邮箱：support@facebook-clone.app'),
            _buildBullet('在线客服：应用内"帮助与反馈"页面'),
            _buildParagraph('我们会在收到您的请求后 30 天内予以回复。'),

            _buildDivider(),
            _buildTitle(context, '附录：法律依据'),
            _buildBullet('《中华人民共和国个人信息保护法》（2021年11月1日施行）'),
            _buildBullet('《中华人民共和国数据安全法》（2021年9月1日施行）'),
            _buildBullet('《中华人民共和国网络安全法》（2017年6月1日施行）'),
            _buildBullet('欧盟《通用数据保护条例》（GDPR，2018年5月25日生效）'),
            _buildBullet('美国《儿童在线隐私保护法》（COPPA）'),
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

  Widget _buildBoldParagraph(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
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
          const Text('  •  ', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
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
    return const Padding(
      padding: EdgeInsets.only(top: 24),
      child: Divider(height: 1, color: AppColors.borderLight),
    );
  }
}