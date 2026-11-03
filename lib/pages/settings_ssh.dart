part of 'settings_page.dart';

extension _SettingsSshSection on _SettingsPageState {
  Widget _buildSshSection() {
    final t = SshText.of(context);
    return Column(
      children: [
        _SectionCard(
          icon: Icons.terminal,
          title: t('SSH 远程与终端', 'SSH & Terminal'),
          children: [
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(t('SSH 主机与终端', 'SSH hosts & terminal')),
              subtitle: Text(
                t(
                  '连接服务器或虚拟机，远程运行脚本',
                  'Connect to servers or VMs and run scripts remotely',
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
