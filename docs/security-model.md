# python_runner 安全模型

本文档记录当前应用的主要安全边界、已落地的防护和仍需收敛的风险。

## 自动更新

- GitHub Release 自动更新只接受 APK asset。
- APK 自动下载安装前必须具备同名 `.sha256` asset，例如 `app-release.apk.sha256`。
- Dart 侧会下载 `.sha256` 文件内容并解析真实的 64 位十六进制 SHA-256。
- Dart 与 Android 原生 MethodChannel contract 都要求 `startApkDownload` / `downloadAndInstallApk` 传入合法 SHA-256；缺失、空值或格式错误会在 bridge 边界被拒绝。
- Android 下载器在下载完成后计算 APK SHA-256，只有与期望值一致才保留文件并进入安装流程。
- 缺失 checksum、checksum 解析失败、格式错误或校验不匹配时，不会自动安装。
- 旧的无 checksum 下载状态不能继续完成安装；恢复任务和安装已完成文件时仍会重新检查任务中的 SHA-256。
- 网络调试代理或不安全证书选项影响全局 `HttpClient` 时，自动安装会被阻止，用户只能手动打开 Release 页面下载验证。

## 网络调试与请求覆盖

- 网络调试可配置代理和不安全证书信任，用于脚本调试。
- 这些选项当前通过 Dart `HttpOverrides.global` 生效，会影响同进程中的 Dart HTTP 请求。
- 为降低更新链路风险，代理或不安全证书启用时自动更新安装路径会 fail closed。
- 请求覆盖配置保存前会校验 JSON，加载到损坏配置时会保留原始字符串并暴露 `configError` 供 UI 提示。
- Python HTTP hook 对响应体做内存限制：图片最大 30 MB，文本/JSON 默认 10 MB，音视频只记录 metadata。

## 运行时边界

- Chaquopy 与 Linux-like 运行时包环境相互独立。
- 项目型脚本只能在 Linux-like 运行时执行；Linux-like 未就绪时项目执行 fail-fast。
- 普通脚本偏好 Linux-like 但运行时不可用时会回退 Chaquopy，并在终端输出明确警告。
- Linux-like 运行环境包安装时会校验 manifest 中的 SHA-256。

## 文件与权限

- 脚本名和项目路径会经过规范化，拒绝路径穿越、路径分隔符和控制字符。
- Main/debug manifest 仍包含完整文件访问、悬浮窗、MT DocumentsProvider 和 cleartext traffic 等高级/调试能力。
- Release manifest overlay 会移除 `MANAGE_EXTERNAL_STORAGE`、`SYSTEM_ALERT_WINDOW`、MT DocumentsProvider / WakeUpActivity，并设置 `usesCleartextTraffic=false`。
- `REQUEST_INSTALL_PACKAGES` 在 release 中保留，仅用于应用内 APK 更新安装流程。
- Gradle `verifyReleaseManifestPolicy` 会检查合并后的 release manifest，防止高危权限、MT provider/activity 或 cleartext traffic 回归。

## Release 门禁

- CI 会运行 `flutter analyze --fatal-infos`、`flutter test`、debug APK 构建和 release APK 构建。
- CI release 链路使用临时签名 key 构建 APK，并显式执行 `verifyReleaseManifestPolicy`、`reportReleaseApkSize`、`apksigner verify`。
- CI 会检查 proot 相关 `.so` 在最终 APK 中为 ZIP_STORED，避免 release 重打包破坏 Linux-like runtime。
- CI 会上传 `build/app/reports/apk-size/release-size.txt` 作为 size report artifact。

## 已知待办

- targetSdk 仍为 28，尚未满足 Google Play 当前政策要求。
- MethodChannel 仍以字符串 method 和动态 Map 传参为主，后续需要 typed contract 或 Pigeon。
- 仍需明确 Play/basic 与 advanced/sideload 的渠道策略，尤其是 targetSdk、Linux-like/proot 能力和权限差异。
