# Fuck My Shit Mountain Audit Report

**Project:** python_runner
**Audit mode:** full
**Date:** 2026-06-13
**Reviewer:** Codex / GPT-5

---

## 1. Executive Summary

本次是对 2026-06-11 审计后的复审。结论很明确：上一轮最危险的几个问题已经大幅收敛。自动更新现在会解析同名 `.sha256` asset，缺失 checksum 时阻止自动安装；release overlay 会移除 `MANAGE_EXTERNAL_STORAGE`、`SYSTEM_ALERT_WINDOW`、MT DocumentsProvider 和明文流量；Gradle release 打包后会重新签名并运行 `apksigner verify`；CI 已经补上 `flutter analyze --fatal-infos` 和 `flutter test`；`flutter analyze --fatal-infos` 当前无问题，`flutter test` 当前 154 passed、1 skipped。

后续修复已经补齐两项发布级缺口：CI release 链路现在会构建 release APK、运行 manifest policy、size report、`apksigner verify` 和 proot `.so` ZIP_STORED 检查；APK 更新 checksum 也已下沉到 Dart/Kotlin bridge contract 与 Android `DownloadManager` 边界。当前主要发布 blocker 已集中到 `targetSdk = 28` 与 Play/basic、advanced/sideload 渠道策略。

维护性也比旧报告好一些，三个大页面已拆成多个 part 文件，Dart/Flutter 页面入口明显变轻。不过 `MainActivity.kt` 仍有 2726 行，`network_inspector_detail.dart` 1278 行，`script_list_actions.dart` 1023 行，`script_runner.py` 1080 行。测试数量增加且覆盖了更多真实行为，但源码字符串断言仍大量存在，适合做防回退护栏，不适合当作关键行为的唯一信心来源。

### Score Dashboard

```text
Security        █████████░  8.6  A   更新 checksum 已在 UI、bridge contract 和 DownloadManager 边界强制校验
Stability       ████████░░  8.0  A   数据库未来版本保护、HTTP 存储错误测试、日志/记录上限都已加强，剩余风险主要来自大文件改动面
Performance     ████████░░  7.5  A   HTTP body/image cap 与 APK size budget 已补，但内置 Python 包和 minify/shrink 关闭仍有体积压力
Testing         ███████░░░  7.4  A   154 项测试和 fatal-infos 分析通过，CI release gate 已补齐，但结构/源码字符串测试仍占比较高
Maintainability ██████░░░░  6.5  B   页面拆分有效，MainActivity、网络详情、脚本动作、Python runner 仍超过 1000 行
Design          ███████░░░  7.0  A   validators、runtime abstraction、contract guard 增强明显，剩余风险主要是手写 contract 需防 drift
Release         ███████░░░  7.2  A   CI 已跑 release 验收；targetSdk 28 仍阻断 Play 合规发布
─────────────────────────────────────
Overall         ████████░░  7.5  A
```

Each dimension scored 0.0-10.0. **Higher = better (10 = clean, 0 = shit mountain).** Scores are judgment-based, not formula-based.

### Finding Statistics

| Severity | Count | Active | Closed | Suspected |
|----------|-------|--------|--------|-----------|
| Critical | 0 | 0 | 0 | 0 |
| High | 1 | 1 | 0 | 0 |
| Medium | 4 | 2 | 2 | 0 |
| Low | 3 | 1 | 2 | 0 |
| Info | 1 | 1 | 0 | 0 |
| **Total** | **9** | **5** | **4** | **0** |

## 2. Project Map

项目结构：

- Flutter UI：`lib/main.dart` 初始化主题、权限、Provider、启动更新检查；`lib/pages/*` 承载脚本列表、编辑器、终端、设置、包管理、网络抓包、项目文件视图。上一轮的大页面已拆成 `*_actions.dart`、`*_content.dart`、`*_sections.dart`、`*_widgets.dart` 等文件。
- 状态层：`lib/providers/*` 通过 `ChangeNotifier` 管理脚本、项目、包、执行状态；`ExecutionProvider` 仍协调 runtime、日志、悬浮球、stdin 和 HTTP hook 环境。
- 服务层：`lib/services/*` 包括 SQLite、NativeBridge、更新检查、网络调试配置、请求覆盖配置、HTTP Inspector 持久化和日志导出。
- 运行时抽象：`lib/runtime/*` 将 Chaquopy 与 Linux-like 后端包装为统一能力；项目型脚本对 Linux-like 做 fail-fast，普通脚本可回退 Chaquopy 并输出警告。
- Android 原生：`MainActivity.kt` 仍是 MethodChannel/EventChannel 总入口；`NativeBridgeContract.kt` 和 Dart 侧 `native_bridge_contract.dart` 增加了参数校验；`ScriptFileStore.kt` 分离了一部分脚本文件安全逻辑。
- Python runtime：`script_runner.py` 执行 Chaquopy 脚本，`http_debug_hook.py` 负责 requests/httpx/urllib3/aiohttp/urllib/socket/subprocess 的网络记录与请求覆盖。
- 持久化：SQLite schema version 5；`DatabaseService` 已支持未来 schema 拒绝打开并备份；HTTP Inspector JSON 持久化有记录数和 captured body byte 上限。
- 外部接口：GitHub Release API、APK 下载、PyPI/pip、文件系统/SAF、Android Package Installer、悬浮窗、前台服务、网络调试代理、MethodChannel。
- 安全边界：脚本名/项目路径 validator、ZIP 导入路径归一化、Linux-like rootfs SHA-256、APK checksum、release overlay、FileProvider、DocumentsProvider debug/internal 能力边界、请求覆盖 JSON 校验。
- 测试结构：`test/` 下有 widget、provider、service、runtime、database migration、HTTP hook 行为测试，也仍有大量源码字符串结构测试。
- 发布流程：README 已补 release checklist，Gradle release 会做 manifest policy、APK size report、proot `.so` STORED 重写、重签名和 `apksigner verify`；CI 当前会跑 analyze/test/debug APK/release APK，并执行 release manifest、size、signature、proot `.so` STORED 门禁。

最可能继续出风险的区域：

- Android 发布边界：`targetSdk = 28` 与 Play/basic、advanced/sideload 渠道策略。
- 更新链路：checksum 已下沉到 bridge/native 边界；后续主要是保持 contract 双端一致，防止 drift。
- 原生桥：`MainActivity.kt` 仍聚合大量能力，跨语言 contract 需要继续收敛。
- 测试真实性：结构测试仍很多，不能替代真实 widget/service/device 行为测试。

## 3. Top Risks

1. **High - targetSdk 28 仍阻断公开商店发布。** `android/app/build.gradle` 仍配置 `targetSdk = 28` 并禁用 `ExpiredTargetSdkVersion`，README 也承认不满足 Google Play 要求。
2. **Medium - 关键文件仍过大。** `MainActivity.kt` 2726 行，多个 Dart/Python 文件超过 1000 行，改动面仍大。
3. **Medium - 测试中源码字符串断言仍占比较高。** 这些测试适合防回退，但对真实行为的证明力有限。
4. **Low - APK 体积压力仍未从依赖/profile 层解决。** Chaquopy 内置大量包，release `shrinkResources=false`、`minifyEnabled=false`，目前靠 190MB hard budget 控制。
5. **Low - MethodChannel contract 仍是 Dart/Kotlin 双份手写。** checksum 边界已强制，但长期仍需防止 method/argument schema drift。
6. **Info - 旧报告的大部分高风险项已关闭或显著降级。** 更新 checksum、manifest overlay、CI release gate、HTTP body cap、数据库迁移和依赖升级都有证据。

## 4. Detailed Findings

### Finding: targetSdk 28 仍阻断 Google Play 合规发布

- Severity: High
- Confidence: High
- Category: Release / Security
- Status: Confirmed
- Affected area: Android release configuration
- Evidence:
  - File: `android/app/build.gradle:53`
  - File: `android/app/build.gradle:62`
  - File: `README.md:169`
  - Function / Module: Gradle `android.defaultConfig`
  - Relevant behavior: 构建脚本禁用 `ExpiredTargetSdkVersion` lint，并继续设置 `targetSdk = 28`；README 明确说明当前 targetSdk 不满足 Google Play 要求。
- Problem: 这不是普通兼容性警告，而是公开商店发布策略 blocker。项目为 Linux-like/proot 兼容性保留低 targetSdk 可以理解，但它和当前 Google Play target API 要求冲突。
- Why it matters: 如果目标是稳定公开发布，低 targetSdk 会导致 Play Console 上传/可见性受限；临时升级 targetSdk 又可能破坏 Linux-like direct proot 执行路径。
- Realistic failure scenario: 准备发布新版本到 Play，CI 和本地测试全部通过，但 Play Console 拒绝或限制该更新；团队临时把 targetSdk 提高后，Linux-like runtime 在 Android 新系统上出现 `No such file` 或 exec 限制问题。
- Minimal fix: 明确渠道策略：Play/basic flavor 升级到政策要求 targetSdk 并禁用不兼容能力，advanced/sideload flavor 保留 Linux-like/proot 直接执行能力。
- Better long-term fix: 建立 flavor matrix：targetSdk、manifest 权限、runtime 能力、更新策略和 UI 暴露能力按渠道隔离，并在 CI 中分别构建。
- Regression test suggestion: 添加 Gradle/CI policy test，Play flavor targetSdk 低于政策阈值时失败；为 advanced flavor 保留当前兼容性测试，并补 Android 设备冒烟。
- Estimated effort: 3-10 天，取决于 Linux-like 在 target 35+ 下的替代方案。

### Finding: CI 未运行 release 构建和 release 门禁（已关闭）

- Severity: Medium
- Confidence: High
- Category: Release / Testing
- Status: Closed after follow-up fix
- Affected area: GitHub Actions and release build pipeline
- Evidence:
  - File: `.github/workflows/ci.yml:23-42`
  - File: `android/app/build.gradle:163-200`
  - File: `android/app/build.gradle:202-254`
  - File: `android/app/build.gradle:260-366`
  - Function / Module: `build-apk` workflow, `verifyReleaseManifestPolicy`, `reportReleaseApkSize`, `packageRelease` hook
  - Relevant behavior: CI 运行 `flutter analyze --fatal-infos`、`flutter test` 和 `flutter build apk --debug`；release 专属的 merged manifest 检查、APK size report、proot `.so` STORED 重写、重签名和 `apksigner verify` 只在 release 构建路径执行。
- Problem: 原问题是本地 release 构建脚本已经比上一版强很多，但 PR/CI 没有跑 release 构建，所以最关键的发布门禁仍可能在开发者机器上才暴露。后续已在 `.github/workflows/ci.yml` 中补齐 release APK 构建、manifest policy、size report、`apksigner verify`、proot `.so` ZIP_STORED 检查和 size report artifact。
- Why it matters: release-only 逻辑最容易被 debug CI 漏掉，包括 manifest overlay merge、签名环境变量、Build Tools `apksigner` 发现、zip 重写后签名验证和 size budget。
- Realistic failure scenario: 一次 Gradle/Android plugin 升级后 debug APK 构建通过；release 打包时 `processReleaseMainManifest` 输出路径变化导致 `verifyReleaseManifestPolicy` 找不到 merged manifest，或者 `apksigner` 参数不兼容，直到手动发布才失败。
- Minimal fix: 已完成。CI 使用临时签名 key 跑 `flutter build apk --release`，并显式执行 release 验收门禁。
- Better long-term fix: CI 分为 PR quick gate 和 release candidate gate；release candidate gate 产出 APK、校验签名、生成 `.sha256`、上传 artifact，并把 size report 作为构建产物。
- Regression test suggestion: 保持 `test/ci_release_policy_test.dart` 和 CI release job；后续可把 release APK 也作为短期 artifact 上传用于人工验收。
- Estimated effort: Completed。

### Finding: native APK 下载桥仍允许 checksum-less 下载（已关闭）

- Severity: Medium
- Confidence: High
- Category: Security / Release / Type Safety
- Status: Closed after follow-up fix
- Affected area: NativeBridge update/download contract
- Evidence:
  - File: `lib/services/app_update_manager.dart:237`
  - File: `lib/services/app_update_manager.dart:445-449`
  - File: `lib/services/native_bridge_contract.dart:43`
  - File: `lib/services/native_bridge_contract.dart:61`
  - File: `android/app/src/main/kotlin/com/daozhang/py/NativeBridgeContract.kt:42`
  - File: `android/app/src/main/kotlin/com/daozhang/py/NativeBridgeContract.kt:56`
  - File: `lib/services/native_bridge.dart:455-470`
  - File: `android/app/src/main/kotlin/com/daozhang/py/DownloadManager.kt:273-279`
  - Function / Module: `AppUpdateManager._downloadAndInstallUpdate`, `NativeBridge.startApkDownload`, Kotlin `NativeBridgeContract`, `DownloadManager.completeDownload`
- Relevant behavior: 原问题是 UI 更新入口在无 SHA-256 时阻止自动安装，但 Dart/Kotlin contract 对 `startApkDownload` 只要求 `url` 和 `fileName`，`sha256` 是 optional。后续已将 `downloadAndInstallApk` / `startApkDownload` 的 `sha256` 改为 Dart/Kotlin required argument，并要求 64 位 SHA-256；`DownloadManager` 入口、下载完成和恢复已完成文件时都会要求/复验 checksum。
- Problem: 原安全策略主要放在 `AppUpdateManager` 调用方，而不是 native bridge/download 边界。后续修复已把策略下沉到 Dart/Kotlin contract 和 `DownloadManager`，该绕过路径已关闭。
- Why it matters: 自动更新和 APK 下载是供应链高价值路径，边界层应 fail closed，而不是依赖 UI 层每个调用点都记得传 checksum。
- Realistic failure scenario: 后续开发者为了“手动下载 APK”复用 `NativeBridge.downloadAndInstallApk(url, fileName)`；Dart contract 通过，Kotlin 下载完成后因 sha256 为空跳过校验，然后打开系统安装器。
- Minimal fix: 已完成。`startApkDownload.sha256` / `downloadAndInstallApk.sha256` 现在是 required non-empty 且必须匹配 SHA-256 格式。
- Better long-term fix: 使用 typed request：`VerifiedApkUpdateRequest { url, fileName, version, sha256, source }`，native 层拒绝 `source=update` 且 sha256 为空的请求。
- Regression test suggestion: 保持 `native_bridge_contract_test.dart`、`download_engine_structure_test.dart` 和 release/update 相关测试；后续可补 JVM/instrumentation test 直接覆盖 `DownloadManager` mismatch 删除文件。
- Estimated effort: Completed。

### Finding: 核心文件仍超过合理大小并混合多类职责

- Severity: Medium
- Confidence: High
- Category: Maintainability / Design
- Status: Confirmed
- Affected area: Native bridge, network inspector, script actions, Python runner
- Evidence:
  - File: `android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt:1-2726`
  - File: `lib/pages/network_inspector_detail.dart:1-1278`
  - File: `lib/pages/script_list_actions.dart:1-1023`
  - File: `android/app/src/main/python/script_runner.py:1-1080`
  - Function / Module: `MainActivity`, `_BodyFullViewPageState`, script list action mixin, Python runner
  - Relevant behavior: 页面入口已拆分，但业务动作、UI 详情、runtime 调度、pip/package、文件选择器、更新、悬浮球等仍集中在较大文件中。
- Problem: 违反 Single Responsibility (1.1)、File Size Limit (1.2)、Function/Method Size (1.3)、Low Coupling (2.1)。这不是立即崩溃的问题，但会提高每次发布前变更的回归概率。
- Why it matters: 大文件会隐藏隐式依赖和跨功能状态，review 难度高；尤其 `MainActivity.kt` 是跨语言边界，任何 MethodChannel 修改都可能影响不相关能力。
- Realistic failure scenario: 修改 Linux-like package install 逻辑时误改 `MainActivity.kt` 的 shared process/log/status helper；源码字符串测试仍通过，但设备上某个 event channel 或 runtime 状态异常。
- Minimal fix: 继续沿着已有拆分方向推进：把 update/download、Linux-like package management、file picker、floating ball handler 从 `MainActivity` 拆出能力类；把网络详情的 JSON tree、full body viewer、image preview 分离到独立 widget 文件。
- Better long-term fix: 使用 typed channel/Pigeon 或手写 command handler registry，让 `MainActivity` 只负责注册和分发。
- Regression test suggestion: 拆分前冻结 MethodChannel method names、参数、错误码；拆分后对每个 handler 做 contract/unit test，避免纯字符串测试成为唯一护栏。
- Estimated effort: 3-8 天，建议分批做。

### Finding: 测试套件仍大量依赖源码字符串断言

- Severity: Medium
- Confidence: High
- Category: Testing / Maintainability
- Status: Confirmed
- Affected area: Test suite authenticity
- Evidence:
  - File: `test/download_engine_structure_test.dart:10-95`
  - File: `test/runtime_linux_like_native_bridge_test.dart:10-407`
  - File: `test/ui_theme_cleanup_test.dart:10-327`
  - File: `test/network_frontend_test.dart:9-56`
  - File: `test/release_manifest_policy_test.dart:10-23`
  - Function / Module: Source structure tests
  - Relevant behavior: 多个测试读取源码后 `contains(...)` 或 `isNot(contains(...))`，验证 token 是否存在，而不是验证真实行为或构建产物。
- Problem: 这些测试对防止误删某些代码片段有价值，但容易出现假阳性和假阴性。代码保留字符串但行为失效时测试仍通过；重构后行为正确但字符串变化时测试失败。
- Why it matters: 当前 `flutter test` 全绿是好信号，但关键发布路径如 merged release manifest、APK 签名、native 下载 checksum enforcement 和 Linux-like device behavior 仍需要更真实的测试层。
- Realistic failure scenario: `verifyReleaseManifestPolicy` 字符串存在，因此测试通过；但 Gradle task wiring 或 merged manifest 输出路径变化导致 release 构建时才失败。
- Minimal fix: 保留少量结构测试作为迁移护栏，但每个 release/security finding 对应至少一个行为测试或构建级测试。
- Better long-term fix: 为 MethodChannel contract、release manifest merge、download manager checksum、HTTP hook body cap 建立行为测试金字塔，逐步删除脆弱 token assertions。
- Regression test suggestion: 用 `flutter test` 行为测试覆盖 `UpdateService` checksum fetch 失败/成功；用 Gradle CI job 覆盖 release manifest；用 JVM/Robolectric 或 instrumentation 覆盖 `DownloadManager` checksum mismatch 删除文件。
- Estimated effort: 2-5 天分阶段替换。

### Finding: 安全文档部分落后于当前 release overlay（已关闭）

- Severity: Low
- Confidence: High
- Category: Documentation / Release
- Status: Closed after documentation update
- Affected area: Security documentation
- Evidence:
  - File: `docs/security-model.md:33-40`
  - File: `android/app/src/release/AndroidManifest.xml:4-17`
  - File: `android/app/build.gradle:163-200`
  - Function / Module: security model documentation, release manifest overlay
  - Relevant behavior: `docs/security-model.md` 仍写 release manifest 当前包含完整文件访问、cleartext 仍为 true、MT DocumentsProvider 仍导出、仍需补 release manifest 快照测试；但 release overlay 已 remove 高危权限/provider 并设置 `usesCleartextTraffic=false`，Gradle 也有 merged manifest policy。
- Problem: 原问题是文档和代码状态不一致。安全文档是发布评审和后续维护的重要入口，落后会误导发布决策。后续已更新 `docs/security-model.md`，明确 release overlay、bridge checksum、CI release gate 和剩余 targetSdk/channel 待办。
- Why it matters: 后续维护者可能根据文档重复做已完成工作，或误判 release 仍暴露某些权限；也可能忽略真正未解决的 targetSdk/CI release gate。
- Realistic failure scenario: 发布前 checklist 查看 `security-model.md`，以为 release cleartext/provider 仍未收敛，临时修改错误文件；或者反过来忽视现有 Gradle policy 的维护。
- Minimal fix: 已完成。`docs/security-model.md` 现在区分 main/debug manifest 与 release overlay，并把剩余待办聚焦到 targetSdk/channel strategy。
- Better long-term fix: 在 README/security model 中维护 capability matrix：debug、release、advanced/sideload、Play/basic 各自权限和能力。
- Regression test suggestion: 保持 release checklist review，避免安全模型再次落后于 manifest/CI 实现。
- Estimated effort: Completed。

### Finding: APK 体积压力仍主要靠预算兜住，未从 profile 层解决

- Severity: Low
- Confidence: High
- Category: Performance / Release / Dependency Weight
- Status: Confirmed
- Affected area: Android packaging and Python dependency bundle
- Evidence:
  - File: `android/app/build.gradle:75-111`
  - File: `android/app/build.gradle:136-140`
  - File: `android/app/build.gradle:202-254`
  - File: `docs/apk-size-report.md:30-53`
  - Function / Module: Chaquopy pip bundle, release build type, `reportReleaseApkSize`
  - Relevant behavior: release 仍内置 pandas/numpy/pillow/lxml/sqlalchemy/matplotlib 等重依赖，`shrinkResources=false`、`minifyEnabled=false`；size budget 为 warning 170MB、hard limit 190MB，最近文档记录 release APK 约 157.1MB。
- Problem: 当前 size budget 能防止体积无限增长，但没有解决“所有用户都下载 full Python batteries”的产品/发布成本。对 sideload 也许可以接受，对公开渠道和弱网更新仍有压力。
- Why it matters: APK 越大，下载失败、安装失败、更新放弃率越高；也会让 checksum 下载/验证路径更重。
- Realistic failure scenario: 再加入一个科学计算或自动化库后 APK 接近 190MB，CI 或本地 release 失败；临时删除依赖又破坏用户脚本兼容。
- Minimal fix: 将 size report 作为 CI artifact，并在 release checklist 中要求说明体积变化来源。
- Better long-term fix: 设计 lite/full runtime profile，核心 APK 内置常用小包，重包按需下载并用 checksum 校验。
- Regression test suggestion: CI 对 release APK 体积趋势做记录；新增测试/脚本列出 Chaquopy package bucket 和增长差异。
- Estimated effort: 1-3 天做 reporting，1-3 周做 profile 化。

### Finding: checksum-less 旧下载入口仍保留（已关闭）

- Severity: Low
- Confidence: High
- Category: Code Consistency / Security
- Status: Closed after follow-up fix
- Affected area: NativeBridge API surface
- Evidence:
  - File: `lib/services/native_bridge.dart:455-457`
  - Function / Module: `NativeBridge.downloadAndInstallApk`
- Relevant behavior: 原行为是 `downloadAndInstallApk(String url, {required String fileName})` 直接转调 `startApkDownload(url, fileName: fileName)`，不接收 checksum。后续已改为 `downloadAndInstallApk(..., required String sha256, String version = '')`，并转调带 checksum 的 `startApkDownload`。
- Problem: 原 API 语义无法传 checksum。该问题已关闭；保留入口时也必须传入合法 SHA-256。
- Why it matters: 安全相关 API 应尽量让危险调用难以写出来。保留旧入口会弱化上一轮 checksum 强制策略的边界感。
- Realistic failure scenario: 后续某个按钮或调试功能复用 `downloadAndInstallApk`，绕过 `AppUpdateManager` 的 checksum 检查。
- Minimal fix: 已完成。保留入口但要求 non-empty sha256。
- Better long-term fix: 以 capability-specific API 替代通用字符串 method：verified update、manual open release page、plain download 分开。
- Regression test suggestion: 保持 contract test 禁止无 sha256 APK install path。
- Estimated effort: Completed。

### Finding: 旧报告关键风险已显著关闭

- Severity: Info
- Confidence: High
- Category: Release / Security / Testing
- Status: Confirmed
- Affected area: Remediation progress
- Evidence:
  - File: `lib/services/update_service.dart:4-53`
  - File: `lib/services/app_update_manager.dart:236-249`
  - File: `android/app/src/release/AndroidManifest.xml:4-17`
  - File: `.github/workflows/ci.yml:1-42`
  - File: `assets/python_hooks/http_debug_hook.py:170-218`
  - File: `lib/services/database_service.dart:55-88`
  - Function / Module: update checksum, release overlay, CI, HTTP body cap, database migration guard
  - Relevant behavior: 自动更新缺 checksum 阻止安装、release overlay 移除高危权限/provider/cleartext、CI 跑 analyze/test、HTTP hook 限制 body preview、数据库未来 schema 备份并拒绝打开。
- Problem: 这是正向观察，不是缺陷。
- Why it matters: 说明 2026-06-11 报告中的 High/Medium 风险大部分已被实质处理，剩余工作集中在发布策略和测试真实性。
- Realistic failure scenario: 不适用。
- Minimal fix: 不适用。
- Better long-term fix: 将这些修复固化到 CI release gate 和文档 checklist，避免回归。
- Regression test suggestion: 保留并增强当前 update、manifest、database、HTTP hook 测试；把 release-only 检查迁入 CI。
- Estimated effort: 不适用。

## 5. Security Concerns

| Issue | Severity | Status | Notes |
|-------|----------|--------|-------|
| Native APK 下载桥允许空 checksum | Medium | Closed | Dart/Kotlin contract 和 DownloadManager 已要求合法 SHA-256 |
| 旧 `downloadAndInstallApk` API 暴露 checksum-less 语义 | Low | Closed | 入口保留，但现在必须传入合法 SHA-256 |
| Release manifest 高危权限/provider | Closed | Confirmed | release overlay 和 Gradle policy 已落地 |
| 网络调试影响更新链路 | Closed/Contained | Confirmed | `AppUpdateManager` 在 global proxy/insecure cert 时阻止自动安装 |

## 6. Stability Concerns

| Issue | Severity | Status | Notes |
|-------|----------|--------|-------|
| 大文件改动面导致回归风险 | Medium | Confirmed | `MainActivity.kt` 和多个 1000+ 行文件仍是稳定性间接风险 |
| HTTP Inspector 持久化异常 | Closed/Contained | Confirmed | test factory 可 `throwOnStorageError=true`，测试已覆盖失败路径 |
| 数据库未来 schema | Closed | Confirmed | 当前会拒绝打开并备份，不再静默降级 |
| Runtime fallback | Contained | Confirmed | 普通脚本回退会输出警告，项目脚本 Linux-like 不可用 fail-fast |

## 7. Performance Concerns

| Issue | Severity | Status | Notes |
|-------|----------|--------|-------|
| APK 体积压力 | Low | Confirmed | 有 170MB warning、190MB hard budget，但未做 lite/full profile |
| HTTP body/image preview | Closed | Confirmed | hook 侧 image 30MB cap、文本 10MB cap，store 侧 24MB cap |
| 大列表/页面渲染 | Low/Contained | Confirmed | 已有 builder/cache 优化，但网络详情 full body 页面仍较重 |

## 8. Testing Gaps

| Gap | Severity | Status | Recommended action |
|-----|----------|--------|--------------------|
| CI 不跑 release 构建/门禁 | Medium | Confirmed | 加 release manifest/build smoke |
| 源码字符串测试过多 | Medium | Confirmed | 逐步换成行为/构建/JVM tests |
| Native checksum mismatch 行为 | Low | Partially covered | bridge/structure tests 已补，后续可加 JVM/instrumentation 行为测试 |
| Device-level Linux-like targetSdk behavior | Medium | Confirmed | target 35+ 分支设备冒烟 |

## 9. Maintainability Concerns

| Area | Evidence | Risk |
|------|----------|------|
| `MainActivity.kt` | 2726 lines | MethodChannel、runtime、pip、update、file picker、floating ball 仍集中 |
| `network_inspector_detail.dart` | 1278 lines | full body viewer、JSON tree、image preview 同文件 |
| `script_list_actions.dart` | 1023 lines | 创建/导入/导出/移动/运行/重命名/删除动作集中 |
| `script_runner.py` | 1080 lines | 执行、stdin、hook fallback、包管理输出处理集中 |

## 10. Type Safety Concerns

| Subtype | Count | Critical | High | Medium | Low |
|---------|-------|----------|------|--------|-----|
| UnsafeBlock | 0 | 0 | 0 | 0 | 0 |
| TypeAssertion | 2 | 0 | 0 | 1 | 1 |
| InputBoundary | 2 | 0 | 0 | 1 | 1 |
| OutputLeak | 0 | 0 | 0 | 0 | 0 |
| BooleanTrap | 2 | 0 | 0 | 0 | 2 |
| StringlyTyped | 4+ | 0 | 0 | 2 | 2 |
| ErrorType | 3 | 0 | 0 | 1 | 2 |

重点：MethodChannel method names、status strings、event keys 和 error codes 仍是 stringly typed。Dart/Kotlin contract 已改善，但仍是两份手写列表，需要防 drift。

## 11. Release Concerns

| Issue | Severity | Status | Notes |
|-------|----------|--------|-------|
| targetSdk 28 | High | Confirmed | 公开商店发布 blocker |
| CI release build gate | Medium | Closed | release APK、manifest、size、signature、`.so` STORED 门禁已进 CI |
| APK size | Low | Confirmed | 有预算但没有 profile 化 |
| README release checklist | Improved | Confirmed | 已加入 `.sha256`、apksigner、权限说明 |

## 12. Architecture Concerns

| Area | Current state | Risk |
|------|---------------|------|
| UI pages | 三个旧大页面入口已拆，部分 action/detail 文件仍大 | 中等维护成本 |
| Native bridge | 增加 contract 和 ScriptFileStore，但 MainActivity 仍聚合过多 | 跨功能回归风险 |
| Runtime abstraction | Chaquopy/Linux-like 抽象清晰 | 正向 |
| Update pipeline | checksum 链路已接入 UI，native 边界仍可加强 | 中等安全边界风险 |

## 13. Documentation Accuracy

| Doc | Current accuracy | Action |
|-----|------------------|--------|
| `README.md` | Mostly accurate | 保留 targetSdk 说明和 release checklist |
| `docs/security-model.md` | Current | 已同步 release overlay、bridge checksum 和 CI release gate |
| `docs/apk-size-report.md` | Useful | 作为 CI artifact 更好 |
| Old audit report | Historical | 不应作为当前状态来源 |

## 14. Configuration Safety

| Config | Current behavior | Risk |
|--------|------------------|------|
| Request headers JSON | 保存前校验，加载坏数据暴露 `configError` | 已改善 |
| Domain rules JSON | 加载错误保留原字符串并暴露 error | 已改善 |
| Network debug proxy/insecure cert | 会影响全局 Dart HTTP，但自动更新安装 fail closed | Contained |
| Runtime backend preference | 普通脚本可回退并警告，项目脚本 fail-fast | Contained |
| Release signing config | env/key.properties，缺失则 release 打包失败 | Good |

## 15. Observability

| Area | Strength | Gap |
|------|----------|-----|
| AppLogger | analyze/test 期间可见关键日志，系统日志可导出 | 日志较噪，测试中 expected error 仍会输出 |
| HTTP Inspector | stats、filter、HAR/export、body truncation | 大型 full body UI 仍需性能关注 |
| Native updater | download progress event 完整 | checksum/security event 可更结构化 |
| Release build | apksigner 输出、size report、CI artifact | 仍需 targetSdk/channel strategy |

## 16. Fallback / Defensive Code Analysis

### Fallback Summary

| Subtype | Count | KeepWithAlert | FailFast | Remove |
|---------|-------|---------------|----------|--------|
| SilentFallback | 2 | 1 | 1 | 0 |
| EmptyCatch | 5+ | 4 | 1 | 0 |
| CompatibilityBranch | 3 | 3 | 0 | 0 |
| SilentCorrection | 1 | 1 | 0 | 0 |
| DefensiveGuess | 2 | 1 | 1 | 0 |

推荐策略：

- KeepWithAlert: 普通脚本 Linux-like 不可用回退 Chaquopy，当前已输出警告。
- FailFast: update-origin APK 下载在 bridge/native 层缺 sha256 时拒绝。
- Keep: HTTP hook 对不可用库的 ImportError 返回、悬浮球 best-effort UI 调用。
- Keep: `downloadAndInstallApk` 旧入口已收紧为必须传入合法 SHA-256。

## 17. Testing Authenticity Analysis

### Confidence Assessment

| Test Area | Real Confidence | Risk | Action |
|-----------|-----------------|------|--------|
| Validators and database migrations | High | Low | Keep |
| RequestOverrideConfig and HTTP store | Medium-High | Low | Keep |
| HTTP hook body cap | Medium-High | Low | Keep |
| UpdateService parsing | Medium | Missing fetch/manager behavior tests | Expand |
| Release manifest policy | Medium-Low | Source/Gradle string test, not merged manifest in CI | Move to Gradle CI |
| Runtime/native bridge structure tests | Low-Medium | Many token assertions | Replace gradually |
| UI theme/design cleanup tests | Low-Medium | Mostly source assertions | Keep as guard, add widget tests for key flows |

### Valuable Tests

- `test/services/database_service_migration_test.dart`
- `test/services/request_override_config_test.dart`
- `test/services/http_inspector_store_test.dart`
- `test/http_debug_hook_behavior_test.dart`
- `test/native_bridge_contract_test.dart`
- `test/execution_provider_optimization_test.dart`
- `test/script_name_validator_test.dart`
- `test/project_path_validator_test.dart`

### Suspicious Tests

- `test/runtime_linux_like_native_bridge_test.dart` 大量 `readAsStringSync` + `contains`。
- `test/ui_theme_cleanup_test.dart` 大量源码 token 断言。
- `test/network_frontend_test.dart` 的 hook/filter 断言主要检查字符串存在。
- `test/release_manifest_policy_test.dart` 没有真正读取 merged release manifest。

### Missing Tests

- `AppUpdateManager` 对缺 checksum、启用 proxy/insecure cert 时不调用 `startApkDownload` 的行为测试。
- `DownloadManager` checksum mismatch 删除 APK 并失败的 native/JVM 行为测试。
- Play/basic flavor targetSdk policy test。

## 18. Type Safety Analysis

### Summary

| Subtype | Count | Critical | High | Medium | Low |
|---------|-------|----------|------|--------|-----|
| UnsafeBlock | 0 | 0 | 0 | 0 | 0 |
| TypeAssertion | 2 | 0 | 0 | 1 | 1 |
| InputBoundary | 2 | 0 | 0 | 1 | 1 |
| OutputLeak | 0 | 0 | 0 | 0 | 0 |
| BooleanTrap | 2 | 0 | 0 | 0 | 2 |
| StringlyTyped | 4+ | 0 | 0 | 2 | 2 |
| ErrorType | 3 | 0 | 0 | 1 | 2 |

优先级：

1. 让 update APK request 在类型/contract 层强制 `sha256`。
2. 用生成式 contract 或 Pigeon 替换 Dart/Kotlin 手写 method lists。
3. 统一 download progress event/error code schema。

## 19. Frontend State Analysis

### Summary

| Subtype | Count | Affected Components |
|---------|-------|---------------------|
| ComponentSize | 2 | Network detail/full body, script list actions |
| StateDuplication | 1 | Network filters/UI detail state |
| PropDrilling | 1 | Main/settings theme callbacks |
| EffectChain | 2 | update dialog progress, settings/network config |
| UIBusinessCoupling | 3 | script actions, update manager dialog, network export |
| DOMasState | 0 | N/A |
| RequestState | 2 | update/download, package install |
| RenderPerf | 1 | large network body/detail |

正向变化：`script_list_page.dart`、`settings_page.dart`、`network_inspector_page.dart` 已拆分，入口文件不再是旧报告里的 1000+ 行。下一步应处理拆出来后仍过大的 action/detail 文件。

## 20. Backend API Analysis

### Summary

| Subtype | Count | Affected Endpoints |
|---------|-------|--------------------|
| ApiConsistency | 1 | MethodChannel |
| Validation | 2 | APK sha256, native args |
| Auth | 0 | N/A |
| NplusOne | 0 | N/A |
| Caching | 0 | N/A |
| ErrorResponse | 1 | string error codes |
| BusinessLogic | 2 | update/runtime flows |
| DataFlow | 2 | APK update, project ZIP |

这个项目没有传统后端 API；主要 API 边界是 MethodChannel、GitHub Release、Python hook JSON。MethodChannel 应继续按内部 backend API 对待。

## 21. Dependency Weight Analysis

### Dependency Scoreboard

| Dependency | Status | Weight | Transitives | Used For | Recommended Action |
|------------|--------|--------|-------------|----------|--------------------|
| Chaquopy pip bundle | Heavy but product-aligned | High | Many native wheels | Built-in Python packages | Keep short-term, split profile long-term |
| `re_editor` local path | Vendored | Medium | Local third_party | Code editor | Keep with upstream tracking |
| Flutter direct deps | Healthy | Medium | Normal | App/runtime UI | Keep |
| Transitive Dart deps | Minor outdated | Low | Locked by SDK/packages | Test/runtime support | Monitor |

`flutter pub outdated` 显示 direct/dev dependencies 均 up-to-date，仅 matcher/meta/package_config/test_api/vector_math/win32/xml 等 transitive 不是 latest，且受当前 resolver/SKD 约束。

## 22. Code Consistency Analysis

| Area | Status | Finding |
|------|--------|---------|
| Dart lint | Clean | `flutter analyze --fatal-infos` 无问题 |
| Gradle style | Mostly okay | build reports 曾提示 Groovy space assignment deprecation，当前未作为 blocking finding |
| Error handling | Improved | config 和 database fail-fast 增强，native update sha256 仍需边界统一 |
| File structure | Better | 大页面拆分后仍有若干大型 action/detail 文件 |
| Tests | Mixed | 行为测试与源码字符串测试并存 |

## 23. Comment Coverage Analysis

| Area | Status | Notes |
|------|--------|-------|
| targetSdk/proot rationale | Good | `build.gradle` 注释解释为何停留 target 28 |
| Update security | Good | `AppUpdateManager` 有 SECURITY 注释，README 有 checksum 说明 |
| Security model | Current | 已同步 release overlay、bridge checksum 和 CI release gate |
| Complex release build hack | Good | `.so` STORED 与 resign 流程有注释 |
| Public API docs | Adequate for app | 不是库项目，不要求 Dart doc 全覆盖 |

## 24. Principles Compliance

当前代码库遵守的一些重要原则：输入路径和脚本名有 validator；数据库未来 schema 不再静默打开；更新链路从 UI 层开始 fail closed；HTTP Inspector 和 hook 都有资源上限；SQLite 操作使用参数化 whereArgs；runtime 后端抽象清晰；release manifest 高危能力已有 overlay 和 Gradle policy。

主要违背原则集中在发布边界和结构复杂度：targetSdk 策略尚未解决；`MainActivity.kt` 等文件仍超过合理规模；测试中 implementation/token assertions 仍偏多；MethodChannel contract 虽已增强，但仍是 Dart/Kotlin 双份手写，需要防 drift。

### Principles Violated

| Principle | Violations | Severity | Affected Areas |
|-----------|------------|----------|----------------|
| Single Responsibility (1.1) | 4 | Medium | `MainActivity`, network detail, script actions, runner |
| File Size Limit (1.2) | 5 | Medium | 1000+ line files |
| Fail-Fast (4.4) | 1 | High | targetSdk release strategy |
| Least Privilege (4.6) | 1 | Low | main/debug manifest still broad, release overlay mitigates |
| Test Behavior (8.1) | 6+ | Medium | source-string tests |
| Configuration Over Hardcoding (9.1) | 1 | Low | release size budget/profile not channelized |
| Timeout Every External Call (10.4) | 0 observed | N/A | updater/native downloads have timeouts |

### Principles Respected

- Fail-closed update UI: missing checksum or global debug proxy blocks auto-install.
- Release least privilege: release overlay removes broad debug/internal capabilities.
- Resource bounds: HTTP records/body previews/log history are bounded.
- Migration safety: newer DB schema is backed up and rejected.
- Contract guard: Dart/Kotlin MethodChannel argument validation catches missing required fields.
- Dependency hygiene: direct Flutter dependencies are current.

## 25. Fallback / Defensive Code Analysis

### Fallback Summary

| Subtype | Count | KeepWithAlert | FailFast | Remove |
|---------|-------|---------------|----------|--------|
| SilentFallback | 2 | 1 | 1 | 0 |
| EmptyCatch | 5+ | 4 | 1 | 0 |
| CompatibilityBranch | 3 | 3 | 0 | 0 |
| SilentCorrection | 1 | 1 | 0 | 0 |
| DefensiveGuess | 2 | 1 | 1 | 0 |

Recommended fallback policy:

- FailFast: release target/profile mismatch; update APK bridge call without sha256 已实现 fail-fast。
- KeepWithAlert: ordinary script runtime fallback.
- Keep: optional Python hook imports and best-effort logging/recording.
- Keep: APK install API can remain because it now requires a valid SHA-256 checksum at the bridge boundary.

## 26. Testing Authenticity Analysis

### Confidence Assessment

| Test Area | Real Confidence | Risk | Action |
|-----------|-----------------|------|--------|
| Analyzer gate | High | Low | Keep `--fatal-infos` |
| Flutter service/model tests | High | Low | Keep |
| HTTP hook behavior | Medium-High | Low | Keep and expand |
| Update parsing | Medium | Manager/native boundary missing | Expand |
| Release manifest policy | Medium-Low | Not executed against merged manifest in CI | Move to Gradle CI |
| Source structure tests | Low-Medium | False confidence | Replace gradually |

### Valuable Tests

见第 17 节。

### Suspicious Tests

见第 17 节。

### Missing Tests

见第 17 节。

## 27. Type Safety Analysis

### Summary

见第 18 节。update download contract 已从 optional string sha256 提升为 required SHA-256 field；后续重点是防止 Dart/Kotlin 双份 contract drift。

## 28. Frontend State Analysis

### Summary

见第 19 节。当前 frontend 最大收益来自继续拆 `network_inspector_detail.dart` 和 `script_list_actions.dart`，而不是引入新状态管理库。

## 29. Backend API Analysis

### Summary

见第 20 节。MethodChannel 是本项目事实上的 backend API，建议继续用 contract tests 和 typed schema 收敛。

## 30. Dependency Weight Analysis

### Dependency Scoreboard

见第 21 节。短期不建议盲删 Python 包，因为产品定位需要“开箱可用”；中长期应做 lite/full profile。

## 31. Recommended Fix Order

### Fix Immediately

| Priority | Issue | Why |
|----------|-------|-----|
| P0 | targetSdk/channel strategy | 公开发布 blocker |

### Fix Before Stable Release

| Priority | Issue | Why |
|----------|-------|-----|
| P1 | 更新 `docs/security-model.md` | 文档和代码状态一致 |
| P2 | 用行为/构建测试替换关键源码字符串测试 | 提升真实 release 信心 |
| P2 | release artifact 生成 `.sha256` 自动化 | 减少人工发布错误 |

### Schedule Later

| Priority | Issue | Why |
|----------|-------|-----|
| P2 | 继续拆 `MainActivity.kt` | 降低跨能力回归成本 |
| P2 | 拆 `network_inspector_detail.dart` | 降低 UI 维护成本 |
| P3 | lite/full runtime profile | 控制 APK 体积和更新成本 |
| P3 | Pigeon/typed channel | 长期降低 stringly typed 风险 |

### Ignore for Now

| Issue | Reason |
|-------|--------|
| Optional Python library ImportError fallbacks | hook 兼容不同环境的合理行为 |
| main/debug manifest broad permissions | release overlay 已隔离，后续由 flavor matrix 解决 |
| 部分 UI token tests | 可暂作防回退护栏，但不要当作行为证明 |

## 32. Quick Wins

| Task | Value | Effort |
|------|-------|--------|
| `startApkDownload` contract 要求 non-empty sha256 | 已完成 | Done |
| `downloadAndInstallApk` 要求 non-empty sha256 | 已完成 | Done |
| CI 跑 release build / manifest / signature / size / `.so` checks | 已完成 | Done |
| 更新 `docs/security-model.md` | 消除文档误导 | 30-60 分钟 |
| `AppUpdateManager` 补 mock bridge 行为测试 | 证明缺 checksum/proxy 时不会下载 | 3-6 小时 |
| 把 size report 上传为 CI artifact | 体积趋势可见 | 1-2 小时 |

## 33. Long-term Refactor Plan

1. Release channel/flavor separation

Motivation: Play 合规 targetSdk 与 advanced Linux-like/proot 能力存在天然冲突。

Approach: 建立 `playRelease`、`advancedRelease`、`debug` flavor，分别定义 targetSdk、permissions、provider、runtime capability 和 update policy。

Risk: 多渠道维护成本上升。

Testing strategy: 每个 flavor 至少跑 manifest policy 和 build smoke；Play flavor targetSdk policy fail-fast。

2. Verified update boundary hardening

Motivation: 更新链路安全策略应在边界层强制，而不是只在 UI manager 里强制。

Approach: Typed `VerifiedApkUpdateRequest`，sha256 required；native download manager 对 update type 缺 sha256 直接失败；普通下载和安装分离。

Risk: 旧 release/旧调用点需要迁移。

Testing strategy: Dart contract、Kotlin contract、DownloadManager checksum mismatch、AppUpdateManager mock bridge tests。

3. Native bridge decomposition

Motivation: `MainActivity.kt` 仍是最大维护风险。

Approach: 先按能力拆 handler，不改变 method names；再迁移到 generated/typed contract；最后补 JVM/instrumentation tests。

Risk: MethodChannel 兼容性断裂。

Testing strategy: contract tests freeze names、required args、error codes、event payload。

4. Test authenticity upgrade

Motivation: 全绿测试需要更接近真实行为。

Approach: 每替换一个源码字符串测试，就新增一个 widget/service/build/native 行为测试；优先 release、update、runtime、HTTP body。

Risk: 初期测试编写成本增加。

Testing strategy: 保留少量 structure smoke，行为测试成为 release 信心来源。

5. Runtime/package profile

Motivation: APK 体积会继续影响下载安装体验。

Approach: lite/full profile，重包按需下载并 checksum 校验；CI 记录 size trend。

Risk: 首次使用某些包时需要额外下载。

Testing strategy: weak network install/update tests、package availability tests、size budget CI。

---

Verification performed:

- `flutter --version`: Flutter 3.44.0 stable, Dart 3.12.0。
- `flutter analyze --fatal-infos`: No issues found。
- `flutter test`: 154 tests passed, 1 skipped。
- `flutter pub outdated`: direct dependencies and dev_dependencies all up-to-date; only resolver-constrained transitive packages are not latest。
- File size scan: `MainActivity.kt` 2726 lines, `network_inspector_detail.dart` 1278, `script_list_actions.dart` 1023, `script_runner.py` 1080。
- Git worktree note: repository was already dirty before this audit; this report was added without reverting user changes。
