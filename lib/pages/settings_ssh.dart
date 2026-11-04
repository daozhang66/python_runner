part of 'settings_page.dart';

extension _SettingsSshSection on _SettingsPageState {
  Widget _buildSshSection() {
    final t = SshText.of(context);
    return Column(
      children: [
        _SectionCard(
          icon: Icons.terminal,
          title: t('终端与 SSH', 'Terminal & SSH'),
          children: [
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(t('本机终端与 SSH 主机', 'Local terminal & SSH hosts')),
              subtitle: Text(
                t(
                  '本机 Shell、Python 交互环境，连接服务器或虚拟机远程运行脚本',
                  'Local shell, Python console, and remote hosts to run scripts on',
                ),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SshProfilesPage(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
