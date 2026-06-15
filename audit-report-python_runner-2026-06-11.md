# Fuck My Shit Mountain Audit Report

**Project:** python_runner
**Audit mode:** full
**Date:** 2026-06-11
**Reviewer:** Codex / GPT-5

---

## 1. Executive Summary

python_runner 是一个 Flutter + Android 原生 + Chaquopy/Linux-like 双运行时的 Android Python 脚本运行器。整体不是“不可救”的状态：脚本名/项目路径校验、ZIP 导入限额、Linux-like rootfs SHA-256 校验、HTTP Inspector 持久化上限、执行日志裁剪、SQLite 迁移这些关键点已经有实际工程防护；`flutter test` 当前 131 项全过，`flutter analyze` 没有 error。

主要风险集中在稳定公开发布之前必须处理的边界：自动更新 APK 的完整性链路没有真正接上 SHA-256/签名钉扎；Android 发布配置停留在 `targetSdk = 28` 并禁用了过期 target 检查；release manifest 同时声明完整文件访问、安装 APK、悬浮窗、明文流量和一个可访问私有目录的 DocumentsProvider。这些不是单个 bug，而是“发布政策 + 安全边界 + 可维护性”交叉处的风险。

维护性是当前最大长期成本。`MainActivity.kt`、`script_list_page.dart`、`settings_page.dart`、`network_inspector_page.dart` 等文件都远超 1000 行，原生层 MethodChannel 把脚本文件、项目 ZIP、Python 执行、pip、Linux-like runtime、APK 更新、悬浮球、文件选择器放在一个类里。短期可以局部加防线，长期需要按能力拆分边界，否则每次功能迭代都会提高回归概率。

### Score Dashboard

```text
Security        █████░░░░░  5.5  C   更新 APK 缺少强制摘要/签名校验，manifest 权限面和明文流量较宽
Stability       ██████░░░░  6.5  B   运行日志/HTTP 记录有上限，但多处 silent fallback 和测试期持久化异常未失败
Performance     ██████░░░░  6.0  B   大对象/日志有裁剪，但图片响应可无上限 base64，release 体积压力明显
Testing         █████░░░░░  5.5  C   131 项测试通过；但大量测试读源码字符串，关键发布/更新路径缺少行为级覆盖
Maintainability ████░░░░░░  4.5  C   多个超大文件和跨层职责混合，局部修改的认知成本高
Design          █████░░░░░  5.0  C   有 validators/runtime abstraction，但 SRP、低耦合、fail-fast 违反较集中
Release         ████░░░░░░  4.0  C   targetSdk 28 不满足当前 Play 要求，未发现 CI，release shrink/minify 关闭
─────────────────────────────────────
Overall         █████░░░░░  5.3  C
```

Each dimension scored 0.0-10.0. **Higher = better (10 = clean, 0 = shit mountain).**

### Finding Statistics

| Severity | Count | Confirmed | Suspected |
|----------|-------|-----------|-----------|
| Critical | 0 | 0 | 0 |
| High | 2 | 2 | 0 |
| Medium | 9 | 8 | 1 |
| Low | 5 | 5 | 0 |
| Info | 1 | 1 | 0 |
| **Total** | **17** | **16** | **1** |

## 2. Project Map

项目结构：

- Flutter UI：`lib/main.dart` 初始化主题、权限、Provider、启动更新检查；`lib/pages/*` 承载脚本列表、编辑器、终端、设置、包管理、网络抓包、项目文件视图。
- 状态层：`lib/providers/*` 使用 `ChangeNotifier` 管理脚本、项目、包、执行状态；`ExecutionProvider` 同时协调 runtime 选择、日志、悬浮球、stdin、HTTP hook 环境。
- 服务层：`lib/services/*` 包括 SQLite、NativeBridge、更新检查、网络调试配置、请求覆盖配置、HTTP Inspector 持久化、日志导出。
- 运行时抽象：`lib/runtime/*` 将 Chaquopy 与 Linux-like 后端包装成统一能力；Linux-like 仍大量依赖 Kotlin 原生桥。
- Android 原生：`MainActivity.kt` 是 MethodChannel/EventChannel 总入口，处理文件 IO、脚本执行、pip、Linux-like runtime、下载更新、文件选择器、悬浮球等；`LinuxLikeRuntimeManager.kt` 负责 rootfs 下载/校验/解压/proot；`DownloadManager.kt` 和 `ApkInstaller.kt` 负责 APK 更新下载与安装。
- Python runtime：`android/app/src/main/python/script_runner.py` 与 `http_debug_hook.py` 负责 Chaquopy 执行与 HTTP hook；`assets/python_hooks/http_debug_hook.py` 是同类 hook 资产。
- 持久化：SQLite 数据库版本 5，表为 `scripts` 和 `script_groups`；SharedPreferences 存储设置；HTTP Inspector 使用 JSON 文件持久化；Linux-like runtime 放在 app private files。
- 外部接口：GitHub release 更新 API、APK 下载、PyPI/pip、文件系统/SAF、Android Package Installer、悬浮窗、前台服务、网络调试代理。
- 安全边界：脚本/项目路径 validator、ZIP 导入路径归一化、rootfs SHA-256、APK 下载可选 SHA-256、FileProvider、DocumentsProvider、安装未知来源权限、MANAGE_EXTERNAL_STORAGE。
- 测试结构：`test/` 下有行为测试、Provider/model/service 测试，也有大量源码字符串结构测试；未发现 `.github/workflows`。
- 发布流程：README 只记录 `flutter build apk --release`；Gradle release 手动重写 APK zip 并重新签名；未发现自动化产物校验、回滚、渠道隔离。

最可能出风险的区域：

- 更新链路：`UpdateService -> AppUpdateManager -> NativeBridge -> MainActivity -> DownloadManager -> ApkInstaller`。
- Android 发布边界：`android/app/build.gradle` 与 `AndroidManifest.xml`。
- 原生桥：`MainActivity.kt` 的 MethodChannel 参数解析和能力聚合。
- 网络调试链路：Dart 配置、Python hook、HTTP Inspector 持久化。
- 大型 UI 页面：`script_list_page.dart`、`settings_page.dart`、`network_inspector_page.dart`。

## 3. Top Risks

1. **High - 自动更新 APK 完整性校验没有接入发布元数据。** 原生下载器支持 SHA-256，但 Dart 更新流程没有传递摘要，安装器只校验包名。
2. **High - Android 发布配置停留在 targetSdk 28 且禁用过期检查。** 当前 Google Play target API 要求与此冲突，且会绕过新版平台安全行为。
3. **Medium - Release manifest 权限和导出面过宽。** 完整文件访问、安装 APK、悬浮窗、明文流量、导出的 DocumentsProvider 同时存在。
4. **Medium - 超大文件和职责混合形成高回归风险。** 多个核心文件超过 1000 行，`MainActivity.kt` 聚合太多能力。
5. **Medium - 测试全绿但大量源码字符串断言降低真实信心。** 多个前端/原生/下载测试只验证源码包含某些 token。
6. **Medium - HTTP hook 对 image/* 响应无上限 base64。** Dart store 后续有限额，但 hook 侧已经可能吃掉大内存。
7. **Medium - Silent fallback 和空 catch 会隐藏配置/运行时问题。** 请求覆盖 JSON、Linux-like fallback、悬浮球桥调用等路径会降级或吞错。
8. **Medium - 缺少 CI 与发布门禁。** 本地测试可跑，但没有发现自动化分析、测试、构建、签名产物校验。
9. **Medium - 默认打包 Python 依赖和 release 不压缩导致体积/更新成本高。** Chaquopy 预装大量重依赖，release 关闭 shrink/minify。
10. **Low - README 网络调试说明落后于 hook 能力。** 文档只列 `requests/httpx/urllib`，代码还 hook 了 `urllib3/aiohttp/socket/subprocess`。

## 4. Detailed Findings

### Finding: 自动更新 APK 缺少强制摘要或签名钉扎

- Severity: High
- Confidence: High
- Category: Security / Release
- Status: Confirmed
- Affected area: App update pipeline
- Evidence:
  - File: `lib/services/update_service.dart:4-27`
  - File: `lib/services/update_service.dart:183-211`
  - File: `lib/services/app_update_manager.dart:197-211`
  - File: `lib/services/app_update_manager.dart:382-387`
  - File: `lib/services/native_bridge.dart:459-470`
  - File: `android/app/src/main/kotlin/com/daozhang/py/DownloadManager.kt:273-279`
  - File: `android/app/src/main/kotlin/com/daozhang/py/ApkInstaller.kt:55-69`
  - Function / Module: `UpdateService.parseLatestReleaseResponse`, `AppUpdateManager._downloadAndInstallUpdate`, `NativeBridge.startApkDownload`, `DownloadManager.completeDownload`, `ApkInstaller.validateApk`
  - Relevant behavior: NativeBridge 和 DownloadManager 支持 `sha256`，但 release asset 只解析 name/url/size/contentType；下载更新调用没有传 `sha256`；安装前只校验 APK 包名匹配当前包名。
- Problem: 更新链路看起来预留了 SHA-256 校验，但真实 release 元数据没有摘要字段，也没有强制要求 checksum asset 或签名证书指纹。包名校验只能防止安装其他包名，不能证明 APK 是项目信任的发布产物。
- Why it matters: 自动更新是供应链高价值路径。若 GitHub release asset、镜像前缀、下载链路或用户配置的镜像被污染，应用会把一个包名相同但非预期来源的 APK 交给系统安装器。
- Realistic failure scenario: 用户配置 GitHub 镜像前缀；镜像返回被替换的 APK；下载器因 `sha256` 为空跳过校验；安装器解析到相同 packageName 后打开系统安装器；用户确认安装后更新到非预期构建。
- Minimal fix: 在 release 解析中支持强制 checksum，例如同 release 下 `<apk>.sha256` 或 manifest JSON；`AppUpdateManager` 在没有 digest 时拒绝自动安装，只允许“打开 release 页面”。
- Better long-term fix: 对 APK 签名证书做钉扎校验，记录当前安装包签名指纹，下载后比对 archive signing certificate；将更新 manifest 与 APK 放入同一受信任发布流程。
- Regression test suggestion: 新增 `UpdateService` 行为测试，验证带 checksum 的 release 会传入 `_bridge.startApkDownload(... sha256: ...)`，缺失 checksum 时不会调用下载并显示安全错误；新增 Android 单元/仪器测试覆盖签名指纹不匹配失败。
- Estimated effort: 1-2 天。

### Finding: targetSdk 28 与当前公开发布要求冲突

- Severity: High
- Confidence: High
- Category: Release / Security
- Status: Confirmed
- Affected area: Android build configuration
- Evidence:
  - File: `android/app/build.gradle:49-60`
  - Function / Module: Gradle `android.defaultConfig`
  - Relevant behavior: `lint.disable 'ExpiredTargetSdkVersion'`，注释说明 target 29+ 会破坏 direct proot rootfs exec，实际配置 `targetSdk = 28`。
  - External policy: Android Developers “Meet Google Play's target API level requirement” 当前说明新应用和应用更新必须 target Android 15 / API 35 或更高，现有应用需 target Android 14 / API 34 或更高才能继续对更高系统新用户可见。
- Problem: release 配置主动停留在旧 targetSdk，并关闭了过期 target 检查。这可能是为 proot 直接执行 app data 下 ELF 的兼容性折中，但它与 Google Play 当前要求直接冲突，也会使应用绕过新版 Android 行为变更与权限约束。
- Why it matters: 这会阻断正式商店更新，或让应用只能走 sideload/自托管渠道；同时低 targetSdk 在安全评审里会被视为故意规避新平台约束。
- Realistic failure scenario: 准备发布 1.5.1+25 到 Play；构建成功但 Play Console 拒绝上传或限制可见性；团队临时改 targetSdk 后 Linux-like direct proot 执行失效，导致核心 runtime 在 release 前爆雷。
- Minimal fix: 把 targetSdk 升级列为 release blocker，建立 target 35+ 分支验证矩阵；对 Linux-like 采用符合新 target 的执行方案或明确将该能力从 Play 渠道剥离。
- Better long-term fix: 将 distribution 分为 Play 合规渠道和 advanced/sideload 渠道，用 product flavors 隔离 manifest、runtime 能力、更新策略和权限声明。
- Regression test suggestion: 增加 Gradle/CI 检查，读取 `android.defaultConfig.targetSdk`，低于政策阈值时失败；增加 Linux-like target 35+ 设备执行冒烟测试。
- Estimated effort: 3-10 天，取决于 proot 兼容方案。

### Finding: Release manifest 权限面和导出面过宽

- Severity: Medium
- Confidence: High
- Category: Security / Release
- Status: Confirmed
- Affected area: Android manifest and app capabilities
- Evidence:
  - File: `android/app/src/main/AndroidManifest.xml:3-33`
  - File: `android/app/src/main/AndroidManifest.xml:74-90`
  - Function / Module: Android manifest
  - Relevant behavior: Manifest 声明 `MANAGE_EXTERNAL_STORAGE`、`REQUEST_INSTALL_PACKAGES`、`SYSTEM_ALERT_WINDOW`、`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`、媒体/存储权限，并设置 `android:usesCleartextTraffic="true"`；`MTDataFilesProvider` exported=true，`MTDataFilesWakeUpActivity` exported=true。
- Problem: 这些权限和导出组件可能符合“高级脚本运行器”的能力目标，但目前没有通过 flavor/渠道/功能开关隔离。release 默认就携带完整文件访问、安装 APK、悬浮窗、明文网络和私有目录文档提供器，安全审查和商店政策压力都很高。
- Why it matters: 权限越宽，用户设备上的误配置、第三方集成、系统漏洞和社会工程组合风险越高；明文流量默认允许会扩大 MITM 风险。
- Realistic failure scenario: 普通用户只需要运行脚本，但 release APK 请求一组高敏权限；上架审查要求解释或拒审；同时自动更新链路还支持用户配置 GitHub mirror，明文流量默认允许让下载/网络调试路径更难论证安全。
- Minimal fix: 审计每个权限是否 release 必需；将 `usesCleartextTraffic` 改为 false，并用 network security config 只允许显式调试域；将高危能力放入 advanced flavor。
- Better long-term fix: 建立 capability matrix：Play/basic、sideload/advanced、debug 三种 manifest；设置页按渠道隐藏不可用能力并解释原因。
- Regression test suggestion: 增加 manifest 快照测试，release flavor 不允许 `usesCleartextTraffic=true` 和非必要高危权限；对 advanced flavor 单独断言所需权限存在。
- Estimated effort: 1-3 天。

### Finding: MTDataFilesProvider 暴露 app 私有目录的读写能力

- Severity: Medium
- Confidence: Medium
- Category: Security
- Status: Suspected
- Affected area: DocumentsProvider integration
- Evidence:
  - File: `android/app/src/main/AndroidManifest.xml:74-84`
  - File: `android/app/src/main/java/bin/mt/file/content/MTDataFilesProvider.java:80-130`
  - File: `android/app/src/main/java/bin/mt/file/content/MTDataFilesProvider.java:133-193`
  - File: `android/app/src/main/java/bin/mt/file/content/MTDataFilesProvider.java:226-313`
  - File: `android/app/src/main/java/bin/mt/file/content/MTDataFilesProvider.java:341-407`
  - Function / Module: `MTDataFilesProvider`
  - Relevant behavior: Provider root 映射到 app `data`、`android_data`、`android_obb`、`user_de_data`；支持 query/open/create/delete/rename/move；自定义 `mt:setPermissions` 与 `mt:createSymlink`。
- Problem: Provider 有 `android.permission.MANAGE_DOCUMENTS` 保护，这不是普通第三方应用可随意拿到的权限，所以不能断言为任意应用可利用。但 release 内置一个可操作私有数据目录、权限位和 symlink 的 DocumentsProvider，边界很宽，且代码没有明显的 release/debug 隔离。
- Why it matters: 一旦系统文档授权链或特定文件管理器集成误用，应用私有数据、脚本、Linux-like runtime 和配置文件可能被外部文档客户端读取或修改。
- Realistic failure scenario: 用户通过兼容的文档/文件管理器打开该 provider；外部工具修改 app 私有脚本或 runtime 文件；下次执行时运行被修改内容，问题表现为脚本或运行环境随机损坏。
- Minimal fix: 明确该 provider 是否只为调试/MT 管理器高级用户使用；若不是核心 release 能力，放入 debug/advanced flavor；若必须保留，限制 root、禁用 symlink/chmod 或加显式用户开关。
- Better long-term fix: 使用标准 SAF 导出/导入特定目录，不把整个 app data tree 暴露为文档根；对可写区域做 allowlist。
- Regression test suggestion: Manifest/flavor 测试：Play/basic release 不包含 `MTDataFilesProvider`；provider 单元测试验证 docId 不能越过 allowlist。
- Estimated effort: 1-2 天。

### Finding: 核心组件文件过大且职责混合

- Severity: Medium
- Confidence: High
- Category: Maintainability / Design
- Status: Confirmed
- Affected area: Native bridge, UI pages, runtime scripts
- Evidence:
  - File: `android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt:1-2765`
  - File: `lib/pages/script_list_page.dart:1-2641`
  - File: `lib/pages/settings_page.dart:1-2259`
  - File: `lib/pages/network_inspector_page.dart:1-1768`
  - File: `android/app/src/main/python/script_runner.py:1-1080`
  - File: `android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt:1-858`
  - Function / Module: `MainActivity`, main Flutter pages, Python runner
  - Relevant behavior: `MainActivity` MethodChannel 注册从脚本 CRUD、项目 ZIP、执行、pip、文件选择器、更新、runtime、悬浮球全部集中在一个类；多个 UI 页面同时处理界面、业务动作、持久化设置和导航。
- Problem: 违反 SRP 1.1、File Size 1.2、Low Coupling 2.1、Business Logic Independence 7.2。当前代码可运行，但任何一个能力变更都需要进入巨型文件，review 和测试定位成本高。
- Why it matters: 大文件会隐藏交叉状态和隐式依赖；局部修复更新、文件选择器或 runtime 时，容易影响不相关功能。
- Realistic failure scenario: 修改 `MainActivity` 的 APK 更新 channel，误碰脚本执行或 Linux-like install 方法；测试里大量源码字符串断言仍然通过，但设备上某个 MethodChannel 参数路径断掉。
- Minimal fix: 先建立“能力类”边界，不重写逻辑：`ScriptFileChannelHandler`、`ProjectChannelHandler`、`RuntimeChannelHandler`、`UpdateChannelHandler`、`FloatingBallChannelHandler`；Flutter 页面先提取纯 service/action controller。
- Better long-term fix: NativeBridge 使用 typed command/result schema；UI 层只负责渲染和用户意图，业务动作下沉到 provider/service；每个能力有行为测试。
- Regression test suggestion: 拆分前先加 MethodChannel contract tests 和关键设备冒烟测试；拆分后验证每个 method name、参数缺失、错误码与旧行为一致。
- Estimated effort: 5-15 天，建议分阶段。

### Finding: 大量测试断言源码字符串而非行为

- Severity: Medium
- Confidence: High
- Category: Testing / Testing Authenticity
- Status: Confirmed
- Affected area: Test suite
- Evidence:
  - File: `test/download_engine_structure_test.dart:9-57`
  - File: `test/download_engine_structure_test.dart:63-104`
  - File: `test/runtime_linux_like_native_bridge_test.dart:6-140`
  - File: `test/editor_frontend_test.dart:7-31`
  - File: `test/package_manager_frontend_test.dart:7-39`
  - File: `test/ui_theme_cleanup_test.dart:8-329`
  - Function / Module: Frontend/native structure tests
  - Relevant behavior: 多个测试使用 `File(...).readAsStringSync()` 后 `contains(...)` 或 `isNot(contains(...))`。
- Problem: 这些测试能防止误删某些 token，但不能证明功能可执行。实现可能重命名、移动、抽象后行为不变却测试失败；也可能保留字符串但行为损坏而测试通过。
- Why it matters: 当前 `flutter test` 131 项全过容易给出过高信心；关键路径如 APK 更新完整性、Android 签名验证、MethodChannel 真实交互没有同等强度行为测试。
- Realistic failure scenario: 开发者把 `startApkDownload` 字符串保留在注释里，实际调用参数漏传；结构测试通过，但自动更新运行时没有摘要校验或进度事件异常。
- Minimal fix: 把源码字符串测试降级为少量架构 smoke test；为关键路径补 fake bridge/fake HTTP/fake filesystem 的行为测试。
- Better long-term fix: 建立 contract test 层：Dart NativeBridge mock、Kotlin handler JVM test、Flutter widget smoke、Android instrumentation 冒烟。
- Regression test suggestion: 对 `AppUpdateManager` 新增 fake `NativeBridge`，断言 release asset digest 缺失时不会下载，digest 存在时透传；对 HTTP Inspector 用真实 store test 覆盖 body 上限。
- Estimated effort: 2-5 天。

### Finding: HTTP hook 对图片响应无上限 base64 捕获

- Severity: Medium
- Confidence: High
- Category: Performance / Stability
- Status: Confirmed
- Affected area: Python HTTP debug hook
- Evidence:
  - File: `android/app/src/main/python/http_debug_hook.py:170-199`
  - File: `android/app/src/main/python/http_debug_hook.py:228-238`
  - File: `android/app/src/main/assets/python_hooks/http_debug_hook.py:172-181`
  - File: `assets/python_hooks/http_debug_hook.py:172-181`
  - File: `lib/services/http_inspector_store.dart:276-278`
  - Function / Module: `_safe_body_preview`, `_is_preview_truncated`, `HttpInspectorStore`
  - Relevant behavior: hook 注释明确 `image/*` full base64 encode “no size limit”；非图片默认 2MB 限制；Dart store 之后限制 5000 records 和 24MB captured body。
- Problem: Dart store 的总量限制发生在 hook 之后。图片响应在 Python 进程里已经完整 base64 编码，体积膨胀约 33%，大图片或批量图片可能造成 Chaquopy/Linux-like 进程内存峰值。
- Why it matters: 网络调试通常会抓图片、二维码、验证码或接口返回的截图；移动端内存余量有限，调试功能不应因为单个响应导致脚本执行崩溃。
- Realistic failure scenario: 用户开启记录响应体，脚本下载 30MB PNG；hook 将其完整读入并 base64，内存峰值超过 40MB，再通过 bridge 传给 Dart，脚本执行或 UI 卡死。
- Minimal fix: 对 `image/*` 也设置单条上限，例如 1-2MB；超限只存 metadata、content-type、size 和 truncated 标记。
- Better long-term fix: 图片预览使用文件落盘和缩略图策略，UI 只按需加载缩略图，大体积原始 body 不进 JSON bridge。
- Regression test suggestion: Python 单元测试 `_safe_body_preview` 对 3MB image 返回 `media/image metadata` 或 truncated；Dart store 测试单条超限不会膨胀内存。
- Estimated effort: 2-4 小时。

### Finding: 请求覆盖配置 JSON 解析失败会静默丢配置

- Severity: Medium
- Confidence: High
- Category: Stability / Configuration / Fallback
- Status: Confirmed
- Affected area: Request override configuration
- Evidence:
  - File: `lib/services/request_override_config.dart:33-42`
  - File: `lib/services/request_override_config.dart:45-70`
  - File: `android/app/src/main/python/http_debug_hook.py:47-50`
  - Function / Module: `RequestOverrideConfig.parsedHeaders`, `RequestOverrideConfig.load`, hook config load
  - Relevant behavior: `parsedHeaders` catch 后返回 `{}`；domain rules JSON 解析失败时 `_domainRules = []`；Python hook 解析 global headers 异常也降级。
- Problem: Header/domain rules 是用户主动设置的网络调试/覆盖配置，解析失败时静默变成空配置会让请求行为与 UI 预期不一致。
- Why it matters: 网络调试常用于复现线上请求。全局 Cookie/Header 丢失会导致登录态、鉴权或代理行为异常，用户看到的是脚本请求失败，而不是配置格式错误。
- Realistic failure scenario: 用户输入一个尾逗号 JSON header；UI 保存成功；下一次运行时 headers 为空；服务端返回 401；日志里没有清晰指出 header JSON 无效。
- Minimal fix: 保存前校验 JSON，错误时阻止保存并在 UI 显示字段错误；load 失败时保留原始字符串并设置 `configError`。
- Better long-term fix: 用结构化 key/value 编辑器替代手写 JSON，序列化由代码生成。
- Regression test suggestion: `RequestOverrideConfig` 测试无效 JSON 会暴露错误状态且不会默默返回空 map；widget test 验证设置页显示校验错误。
- Estimated effort: 3-6 小时。

### Finding: Linux-like 不可用时自动回退到 Chaquopy 会改变运行语义

- Severity: Medium
- Confidence: High
- Category: Stability / Fallback
- Status: Confirmed
- Affected area: Runtime selection
- Evidence:
  - File: `lib/providers/execution_provider.dart:308-330`
  - File: `lib/providers/execution_provider.dart:395-407`
  - File: `lib/runtime/linux_like_backend.dart:14-15`
  - File: `test/execution_provider_optimization_test.dart:109-122`
  - Function / Module: `ExecutionProvider._resolveExecutableBackendId`, `RuntimeManager`
  - Relevant behavior: Linux-like health check失败时记录 warn 并返回 `RuntimeManager.fallbackBackendId`；测试也断言 fallback 到 Chaquopy。
- Problem: fallback 有日志，不是完全静默；但对需要系统依赖、项目目录、Linux-like site-packages 的脚本来说，Chaquopy fallback 不是等价替代。当前 UI/执行结果可能只表现为后续 import 或路径错误。
- Why it matters: 自动回退适合轻量脚本，但对项目型脚本或用户明确选择 Linux-like 的场景，fail-fast 更能暴露真实问题。
- Realistic failure scenario: 用户选择 Linux-like 运行依赖 `apt`/系统库的项目；runtime 未安装或损坏；系统回退到 Chaquopy，脚本报 `ModuleNotFoundError`，用户误以为包管理或代码有问题。
- Minimal fix: 普通脚本可以“带明确 UI 提示的回退”；项目型脚本和用户显式选择 Linux-like 时默认 fail-fast，并提供按钮“改用 Chaquopy 运行”。
- Better long-term fix: Runtime capability negotiation：脚本/项目声明需要的 backend capability，执行前做 preflight。
- Regression test suggestion: 扩展 `execution_provider_optimization_test`：项目型脚本 Linux-like 不健康时不自动执行 Chaquopy，而返回可见错误状态。
- Estimated effort: 4-8 小时。

### Finding: 测试期间持久化异常只打印不失败

- Severity: Low
- Confidence: High
- Category: Testing / Stability
- Status: Confirmed
- Affected area: HTTP Inspector persistence
- Evidence:
  - File: `lib/services/http_inspector_store.dart:680-702`
  - Command: `flutter test`
  - Relevant behavior: 测试运行时多次打印 `HttpInspectorStore.persist error: MissingPluginException(No implementation found for method getApplicationSupportDirectory...)`，但最终 `All tests passed`。
- Problem: 对生产运行而言，持久化失败打印日志可能是可接受的降级；对测试而言，异常没有让测试失败，说明部分 widget 测试触发了真实 singleton store 而未注入测试目录。
- Why it matters: 测试输出里出现异常但仍全绿，会让后续真实持久化回归被忽略。
- Realistic failure scenario: 修改 path_provider 初始化导致 HTTP 记录无法落盘；测试继续通过，只在日志里打印错误；用户重启后网络记录丢失。
- Minimal fix: 测试环境为 `HttpInspectorStore.instance` 或相关页面注入 test store；在 debug/test 模式提供可选择的 strict persistence failure。
- Better long-term fix: 消除全局 singleton 对 widget test 的隐式依赖，使用 Provider 注入 store。
- Regression test suggestion: 添加测试断言 `flush()` 在注入目录时不打印错误，并能恢复记录；widget test 不允许出现 `HttpInspectorStore.persist error`。
- Estimated effort: 2-4 小时。

### Finding: 缺少 CI 和 release 门禁

- Severity: Medium
- Confidence: High
- Category: Release / Testing
- Status: Confirmed
- Affected area: Repository automation
- Evidence:
  - File: `.github/` directory absent
  - File: `README.md:154-158`
  - Command: `flutter analyze`
  - Command: `flutter test`
  - Relevant behavior: README 只说明 `flutter build apk --release`；未发现 GitHub Actions 或等价 CI 配置。
- Problem: 本地可以运行分析和测试，但没有仓库级门禁保证每次提交、PR、release 都执行相同检查。
- Why it matters: 这个项目跨 Dart/Kotlin/Python/Gradle，人工本地跑测试容易遗漏；尤其当前有很多源码字符串测试，CI 更需要配合真实行为测试和 release 构建。
- Realistic failure scenario: 某次提交修改 Android build script；Dart 测试本地未跑或只跑部分；release 打包时 custom `packageRelease` 重签失败，问题到发版当天才发现。
- Minimal fix: 添加 CI workflow：`flutter pub get`、`flutter analyze`、`flutter test`、`flutter build apk --debug` 或 release dry-run。
- Better long-term fix: 建立 release workflow：签名配置检查、targetSdk policy check、APK checksum 生成、GitHub release manifest 发布、smoke test。
- Regression test suggestion: CI 自身应在 PR 必跑；增加脚本检查 `.github/workflows` 存在且包含 analyze/test/build job。
- Estimated effort: 0.5-1 天。

### Finding: 默认 Python 依赖和 release 配置造成体积压力

- Severity: Medium
- Confidence: High
- Category: Performance / Dependency Weight / Release
- Status: Confirmed
- Affected area: Android build, Chaquopy dependencies
- Evidence:
  - File: `android/app/build.gradle:67-116`
  - File: `android/app/build.gradle:132-137`
  - File: `pubspec.yaml:15-32`
  - Command: `flutter pub outdated`
  - Relevant behavior: Chaquopy pip 默认安装 `numpy`、`pandas`、`matplotlib`、`cryptography`、`lxml`、`sqlalchemy`、`openpyxl`、`python-docx` 等；release `shrinkResources = false`，`minifyEnabled = false`。
- Problem: 对 Python runner 来说预装常用库是产品价值，不应简单删除；但所有用户默认下载/安装这些重量依赖，加上 release 不 shrink/minify，会提高 APK 体积、安装时间、更新成本和冷启动资源压力。
- Why it matters: APK 更新链路已经是高风险路径，体积越大，下载失败、断点续传、校验耗时和用户流失概率越高。
- Realistic failure scenario: 发布新版本仅改 UI，但用户仍需下载包含大量 Python wheel 的大 APK；弱网环境中更新失败，或设备存储不足。
- Minimal fix: 输出 release APK size budget；把依赖分为核心内置、可选包、Linux-like 后装包；打开可行的 resource shrink/minify 验证。
- Better long-term fix: 建立 runtime package profile：lite/full；按渠道或首次使用下载扩展库，并有完整校验。
- Regression test suggestion: CI 记录 APK 大小并超过预算失败；依赖清单变化需更新 `dependency-weight` 文档。
- Estimated effort: 1-3 天。

### Finding: 依赖版本策略存在滞后和停用包

- Severity: Low
- Confidence: High
- Category: Dependency Weight / Release
- Status: Confirmed
- Affected area: Dart dependencies
- Evidence:
  - File: `pubspec.yaml:15-32`
  - File: `pubspec.lock`
  - Command: `flutter pub outdated`
  - Relevant behavior: `file_picker` 当前 8.3.7，latest 11.0.2；`permission_handler` 当前 11.4.0，latest 12.0.3；`flutter_lints` 当前 4.0.0，latest 6.0.0；`isolate_contactor` transitive 被标记 discontinued。
- Problem: 不是立即漏洞证据，但 release 前需要知道哪些旧主版本是有意 pin，哪些是因为 SDK/依赖链没升级。停用 transitive 包提示后续生态维护风险。
- Why it matters: Android targetSdk 升级通常会牵动 permission/file picker 插件主版本；旧插件可能缺少新系统行为适配。
- Realistic failure scenario: targetSdk 升到 35 后，旧 `permission_handler` 或 `file_picker` 在 Android 15/16 权限模型下行为异常，release 前才发现。
- Minimal fix: 为所有“不可升主版本”的依赖写明原因；优先评估 permission/file picker/flutter_lints 升级。
- Better long-term fix: 每月运行 `flutter pub outdated` 并建立依赖升级窗口；对 discontinued transitive 追踪上游替换。
- Regression test suggestion: CI 定期 job 输出 outdated 报告；对权限和文件选择器做 Android 版本矩阵冒烟。
- Estimated effort: 0.5-2 天。

### Finding: 文档没有覆盖 release 风险和当前网络 hook 能力

- Severity: Low
- Confidence: High
- Category: Documentation / Comment Coverage
- Status: Confirmed
- Affected area: README and docs
- Evidence:
  - File: `README.md:120-137`
  - File: `README.md:154-158`
  - File: `test/network_frontend_test.dart:31-40`
  - File: `android/app/src/main/python/http_debug_hook.py`
  - Relevant behavior: README 网络调试列出 `requests`、`httpx`、`urllib`；测试和 hook 还覆盖 socket DNS/connect、subprocess、并存在 `aiohttp`、`urllib3` hook。Release 文档只有 build 命令，没有 targetSdk、权限、更新摘要、签名、回滚说明。
- Problem: 文档不能帮助用户或维护者理解当前能力边界。特别是 release 风险属于“必须被操作手册捕捉”的信息。
- Why it matters: 文档缺失会让后续维护者重复踩坑，例如为什么 targetSdk 被 pin 到 28、自动更新为什么要求 checksum、哪些网络请求会被记录。
- Realistic failure scenario: 新维护者按 README 直接 `flutter build apk --release` 并发布 sideload 包，却不知道 targetSdk/更新校验/权限策略没有达标。
- Minimal fix: 更新 README：网络 hook 支持矩阵、权限说明、release checklist、targetSdk/proot 限制、checksum 发布步骤。
- Better long-term fix: 增加 `docs/release.md` 和 `docs/security-model.md`，把渠道、权限、更新信任链写清楚。
- Regression test suggestion: 文档测试或 checklist test，确认 README 包含 checksum、targetSdk、release signing、rollback 关键字。
- Estimated effort: 2-4 小时。

### Finding: Android release 打包脚本手动改写 APK 后重签，缺少产物校验

- Severity: Medium
- Confidence: High
- Category: Release / Stability
- Status: Confirmed
- Affected area: Gradle release packaging
- Evidence:
  - File: `android/app/build.gradle:160-240`
  - Function / Module: `tasks.whenTaskAdded { packageRelease.doLast { ... } }`
  - Relevant behavior: Release 包完成后遍历 APK zip，把 proot 相关 `.so` 改为 STORED，删除 META-INF 签名文件，再调用 `apksigner sign`。
- Problem: 这是一个合理但脆弱的 release hack。它依赖 task 名称、APK 路径、buildTools、签名参数和 zip entry 处理，且没有后置 `apksigner verify`、zipalign/entry 状态断言或设备安装冒烟。
- Why it matters: 打包脚本出错会直接产出不可安装或运行时 proot 不可执行的 APK；没有 CI 时很难提前发现。
- Realistic failure scenario: Gradle/AGP 升级改变 output path 或 package task；脚本没生效或重签失败；release APK 安装后 Linux-like loader 因压缩/权限问题无法启动。
- Minimal fix: 在脚本末尾运行 `apksigner verify --verbose --print-certs`；断言目标 `.so` entry 是 STORED；构建失败时清晰报错。
- Better long-term fix: 优先使用 AGP packagingOptions/jniLibs 配置解决未压缩 native lib，而不是 post-process APK。
- Regression test suggestion: CI release dry-run 后用脚本检查 APK 中三个 `.so` 的 compression method 和签名验证结果。
- Estimated effort: 0.5-1 天。

### Finding: MethodChannel 参数以字符串和动态 Map 为主，缺少共享 contract

- Severity: Medium
- Confidence: High
- Category: Type Safety / Backend API
- Status: Confirmed
- Affected area: Dart-native bridge
- Evidence:
  - File: `android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt:298-456`
  - File: `lib/services/native_bridge.dart:459-504`
  - File: `lib/services/app_update_manager.dart:407-419`
  - Function / Module: MethodChannel dispatch and event parsing
  - Relevant behavior: Kotlin 用字符串 method name 分发，参数缺失默认 `""` 或 `0`；Dart 侧 event int/long 解析失败使用 fallback。
- Problem: MethodChannel 是项目内部 API，但没有 schema 或 codegen。新增参数如 `sha256` 很容易出现“原生支持但 Dart 没传”的裂缝；event 字段类型错时 Dart 会 fallback，而不是暴露 contract break。
- Why it matters: 这是跨语言边界，编译器无法帮忙；越多能力压在一个 channel 上，越需要强 contract。
- Realistic failure scenario: 原生下载进度字段从 `int` 改成 `String`；UI fallback 到默认值，进度/ETA 异常但没有错误；测试只查源码包含字段名。
- Minimal fix: 为每个 MethodChannel method 定义 Dart/Kotlin 对照表和 contract tests；参数缺失在安全敏感路径 fail-fast。
- Better long-term fix: 使用 Pigeon 或自定义 schema/codegen 生成 typed bridge。
- Regression test suggestion: Fake messenger contract test 覆盖 `startApkDownload` 必须包含 `sha256`；event parser 遇到错误类型在 debug/test 下抛错。
- Estimated effort: 2-5 天。

### Finding: SQLite 迁移缺少 downgrade/失败恢复策略

- Severity: Low
- Confidence: High
- Category: Stability / Release
- Status: Confirmed
- Affected area: Local database
- Evidence:
  - File: `lib/services/database_service.dart:19-28`
  - File: `lib/services/database_service.dart:58-88`
  - File: `lib/services/database_service.dart:90-110`
  - Function / Module: `DatabaseService._initDb`, `_onUpgrade`
  - Relevant behavior: SQLite version 5，提供 incremental `onUpgrade`；没有 `onDowngrade`、备份/恢复或迁移失败处理。
- Problem: 当前升级路径清楚，且使用参数化查询和事务删除 group；风险在 release 回滚或用户安装旧版本时，数据库 downgrade 没有定义行为。
- Why it matters: 移动端 sideload/自动更新场景常见回退安装。schema 升级后装回旧 APK 可能打开失败或数据异常。
- Realistic failure scenario: 发布 v6 schema 后发现问题，用户手动装回 v5；旧代码不能处理新列/版本，脚本列表无法加载。
- Minimal fix: 明确不支持 downgrade 并在启动时给出可恢复错误；关键迁移前备份 DB。
- Better long-term fix: 建立 schema migration test matrix，从 v1-v5 样本库升级，并定义 rollback/export 策略。
- Regression test suggestion: 用 sqflite_common_ffi 或集成测试跑旧 schema fixture -> 当前 schema；模拟迁移失败不破坏原 DB。
- Estimated effort: 0.5-2 天。

### Finding: 全局 HttpOverrides 会影响整个 Dart 进程网络行为

- Severity: Low
- Confidence: High
- Category: Configuration / Security
- Status: Confirmed
- Affected area: Network debug config
- Evidence:
  - File: `lib/services/network_debug_config.dart:6-24`
  - File: `lib/services/network_debug_config.dart:26-50`
  - File: `lib/services/network_debug_config.dart:82-85`
  - Function / Module: `NetworkDebugConfig._applyHttpOverrides`
  - Relevant behavior: 开启网络调试时设置 `HttpOverrides.global`，并可允许不安全证书和代理。
- Problem: 默认是关闭且有日志提醒，这是好的；但一旦开启，它影响整个 Dart VM 的 HTTP 行为，包括更新检查、GitHub API、日志导出相关网络调用等，而不只是用户脚本。
- Why it matters: 调试配置容易被遗忘。全局代理/不安全证书可能改变自动更新或其他应用网络请求的信任模型。
- Realistic failure scenario: 用户为抓包开启 allow insecure；之后检查更新走同一个全局 override，遇到中间人证书也被接受。
- Minimal fix: UI 明确标记“影响应用内所有 Dart 网络请求”；自动更新和安全敏感请求绕过 debug override 或在 insecure enabled 时禁用自动安装。
- Better long-term fix: 网络调试只作用于 Python hook/脚本 session，不修改全局 Dart HTTP。
- Regression test suggestion: NetworkDebugConfig 测试开启 allow insecure 后，AppUpdateManager 自动安装路径被阻止或提示风险。
- Estimated effort: 4-8 小时。

### Finding: 本地路径和归档解压防护做得较好

- Severity: Info
- Confidence: High
- Category: Security / Stability
- Status: Confirmed
- Affected area: Validators, project import, Linux-like runtime
- Evidence:
  - File: `lib/services/script_name_validator.dart:6-24`
  - File: `lib/services/project_path_validator.dart:7-41`
  - File: `android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt:766-834`
  - File: `android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt:883-913`
  - File: `android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt:255-262`
  - File: `android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt:705-718`
  - File: `android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt:737-782`
  - Function / Module: `ScriptNameValidator`, `ProjectPathValidator`, ZIP import, runtime archive install
  - Relevant behavior: 脚本名拒绝 `.`、`..`、斜杠、反斜杠、控制字符；项目 key/path 归一化；ZIP 导入限制 2000 entries、20MB per entry、200MB total；Linux-like rootfs 下载后 SHA-256 校验并解析 tar。
- Problem: 这是正向观察，不是需要修复的缺陷。需要继续保持这些边界，尤其在拆分 `MainActivity` 时不要丢失。
- Why it matters: 这些防护降低了路径穿越、zip bomb、runtime 包篡改的风险，是项目当前安全基础。
- Realistic failure scenario: 后续重构把 `safeProjectFile` 绕开，ZIP 路径检查丢失；现在的测试应保护这些行为。
- Minimal fix: 把这些行为级测试作为重构前保护网。
- Better long-term fix: 将 path/archive safety 抽成独立模块和跨语言 contract。
- Regression test suggestion: 为 ZIP 导入添加包含 `../`、反斜杠、超大 entry、超多 entry 的真实行为测试。
- Estimated effort: 维持即可；补测试 0.5-1 天。

### Finding: Analyzer 仅剩 Flutter Radio API 过期提示

- Severity: Low
- Confidence: High
- Category: Code Consistency / Release
- Status: Confirmed
- Affected area: Settings UI
- Evidence:
  - Command: `flutter analyze`
  - File: `lib/pages/settings_page.dart:546`
  - File: `lib/pages/settings_page.dart:547`
  - File: `lib/pages/settings_page.dart:553`
  - File: `lib/pages/settings_page.dart:554`
  - File: `lib/pages/settings_page.dart:560`
  - File: `lib/pages/settings_page.dart:561`
  - File: `lib/pages/settings_page.dart:593`
  - File: `lib/pages/settings_page.dart:594`
  - Relevant behavior: Flutter 3.32 后 `Radio.groupValue` 和 `Radio.onChanged` deprecated，建议使用 `RadioGroup`。
- Problem: 当前不是功能 bug，但 release 前保持 analyzer clean 有助于让真正问题更显眼。
- Why it matters: 过期 API 在后续 Flutter 版本可能移除；现在 Flutter 3.44 已提示。
- Realistic failure scenario: 升级 Flutter 后 deprecated API 变成 breaking change，设置页构建失败。
- Minimal fix: 按 Flutter 新 API 将相关 Radio 迁移到 `RadioGroup`。
- Better long-term fix: CI 要求 `flutter analyze --fatal-infos` 或至少 release 分支无 info。
- Regression test suggestion: 保留 settings page widget test，确认主题/运行时 picker 仍可选择。
- Estimated effort: 1-2 小时。

## 5. Architecture Concerns

| Sub-category | Findings | Notes |
|--------------|----------|-------|
| Native boundary | F5, F14 | `MainActivity.kt` 聚合过多 MethodChannel 能力，且 contract 非 typed |
| UI layering | F5 | 页面承担业务动作、持久化和渲染 |
| Runtime boundary | F8 | Chaquopy/Linux-like abstraction 已存在，但 fallback 语义需要更明确 |
| Positive architecture | F16 | validators 和 archive/runtime 安全逻辑是可提取的稳定内核 |

Verified checklist:

- `lib/runtime/*` 已有后端抽象，值得保留。
- SQLite service 没有混到 UI 文件里。
- Native bridge 仍是主要瓶颈，需要拆能力边界。

## 6. Security Concerns

| Issue | Severity | Status | Security boundary |
|-------|----------|--------|-------------------|
| F1 自动更新 APK 缺少强制摘要/签名钉扎 | High | Confirmed | Supply chain / update trust |
| F2 targetSdk 28 与平台安全模型脱节 | High | Confirmed | Android platform behavior |
| F3 Manifest 权限面过宽 | Medium | Confirmed | Least privilege |
| F4 DocumentsProvider 暴露私有目录能力 | Medium | Suspected | Cross-app file access |
| F15 全局 HttpOverrides | Low | Confirmed | Network trust |

Verified checklist:

- Rootfs 安装有 SHA-256 校验。
- 脚本名和项目路径校验存在。
- APK 更新链路的 SHA-256 支持只停在原生层，未被 release metadata 强制驱动。

## 7. Stability Concerns

| Issue | Severity | Status | Failure mode |
|-------|----------|--------|--------------|
| F7 图片响应无上限捕获 | Medium | Confirmed | 内存峰值 / 卡顿 / 崩溃 |
| F8 配置 JSON 静默失败 | Medium | Confirmed | 请求行为与 UI 预期不一致 |
| F9 Linux-like 自动回退 | Medium | Confirmed | 运行语义改变 |
| F10 测试持久化异常不失败 | Low | Confirmed | 回归被日志掩盖 |
| F13 SQLite downgrade 未定义 | Low | Confirmed | 回滚安装风险 |

Verified checklist:

- `ExecutionProvider` 有执行 ID，能忽略 stale terminal status。
- `HttpInspectorStore` 有记录数和 body 总量上限。
- 多处错误处理会记录日志，但部分路径需要从“记录后继续”改为“可见错误或 fail-fast”。

## 8. Performance Concerns

| Issue | Severity | Status | Cost |
|-------|----------|--------|------|
| F7 image/* 无上限 base64 | Medium | Confirmed | Python 进程内存和 bridge payload |
| F11 默认重 Python 依赖 + 不 shrink | Medium | Confirmed | APK 体积、下载、安装、更新 |
| F5 巨型页面 | Medium | Confirmed | 构建/维护成本，局部重建风险 |

Verified checklist:

- 终端日志、历史执行、HTTP records 已有裁剪。
- `network_inspector_page` 对部分格式化元数据做缓存。
- `re_editor` path dependency 被 analyzer exclude，避免第三方代码噪音。

## 9. Testing Gaps

| Area | Current confidence | Gap |
|------|--------------------|-----|
| Validators/model/service | Medium-High | 有真实行为测试，继续保留 |
| HTTP Inspector store | Medium | 有 trim/persist 测试，但 widget singleton 仍打印持久化错误 |
| Update pipeline | Low-Medium | release parsing 有测试，但 digest/signature/installer 行为不足 |
| Native Android bridge | Low | 大量源码字符串测试，缺少 JVM/instrumentation contract |
| Release build | Low | 未发现 CI 和 APK post-process verify |

Verified checklist:

- `flutter test` 结果：131 tests passed。
- `flutter analyze` 结果：8 info，均为 deprecated member use。
- 测试真实性需要提升，而不是只增加数量。

## 10. Maintainability Concerns

| Issue | Severity | Status | Affected modules |
|-------|----------|--------|------------------|
| F5 超大文件和职责混合 | Medium | Confirmed | Native bridge, script/settings/network pages |
| F14 非 typed MethodChannel contract | Medium | Confirmed | Dart/Kotlin bridge |
| F6 源码字符串测试 | Medium | Confirmed | Test maintenance |
| F12 文档漂移 | Low | Confirmed | README/docs |

Verified checklist:

- 小型 validator 文件清晰，适合作为拆分目标风格。
- `DatabaseService` 保持相对集中且可读。
- UI design tokens 已抽出，但页面仍过大。

## 11. Design / Principles Concerns

| Principle | Violations | Severity | Affected Areas |
|-----------|------------|----------|----------------|
| Single Responsibility (1.1) | 4+ | Medium | `MainActivity.kt`, `script_list_page.dart`, `settings_page.dart`, `network_inspector_page.dart` |
| File Size Limit (1.2) | 8 | Medium | 多个 800-2700 行核心文件 |
| Low Coupling (2.1) | 2 | Medium | Native MethodChannel, ExecutionProvider |
| Fail-Fast (4.4) | 4 | Medium/High | Update checksum, request override JSON, runtime fallback, event parsing |
| Don't Swallow Errors (6.1) | 5+ | Medium | request config, persistence, floating ball best-effort |
| Dependency Rule (7.1) | 2 | Medium | UI 页面直接协调 service/provider/native side effects |
| Test Behavior, Not Implementation (8.1) | 6+ | Medium | frontend/native structure tests |
| Timeout Every External Call (10.4) | mostly respected | Info | Linux-like download has explicit connect/read timeout |

Verified checklist:

- Principle violations are concentrated, not uniformly bad across repo。
- Path safety、archive limits、store limits 是原则执行较好的区域。

## 12. Release Concerns

| Issue | Severity | Status | Release impact |
|-------|----------|--------|----------------|
| F2 targetSdk 28 | High | Confirmed | Play 发布阻断/限制 |
| F1 更新完整性链路 | High | Confirmed | Supply-chain blocker |
| F3 Manifest 权限 | Medium | Confirmed | 审查和安全说明压力 |
| F11 体积压力 | Medium | Confirmed | 下载/安装/update 成本 |
| F12 文档缺失 | Low | Confirmed | 发布流程不可重复 |
| F17 Analyzer info | Low | Confirmed | Release hygiene |

Verified checklist:

- Release signing config 缺失时 Gradle 会 fail。
- APK post-process 有明确异常，但缺少 verify。
- README release 流程过短，不足以支撑稳定公开发布。

## 13. Documentation Accuracy

| Area | Accuracy | Action |
|------|----------|--------|
| Feature overview | Mostly accurate | 补充网络 hook 支持矩阵 |
| Runtime docs | Partially accurate | 补 targetSdk/proot 限制 |
| Release docs | Weak | 增加 release checklist、checksum、签名、回滚 |
| Security model | Missing | 新增 `docs/security-model.md` |

## 14. Configuration Safety

| Config | Current behavior | Risk |
|--------|------------------|------|
| Request override headers | 无效 JSON 返回空 map | Silent misconfiguration |
| Domain rules | 无效 JSON 清空 | Silent misconfiguration |
| Network debug | 默认关闭，开启后 global override | 影响全局 Dart 网络 |
| Runtime backend | Linux-like 不可用时回退 | 语义改变 |
| GitHub mirror prefix | 可拼接 APK 下载 URL | 需要 checksum 强制兜底 |

## 15. Observability

| Area | Strength | Gap |
|------|----------|-----|
| AppLogger | 系统/崩溃/脚本日志导出 | 测试期日志异常未变成失败 |
| Execution logs | current/history 有裁剪 | fallback 需要 UI 可见状态 |
| HTTP Inspector | 统计、搜索、导出、持久化 | hook 侧大 body 内存峰值 |
| Native update | download progress event | 安全校验状态不完整 |

## 16. Fallback / Defensive Code Analysis

### Fallback Summary

| Subtype | Count | KeepWithAlert | FailFast | Remove |
|---------|-------|---------------|----------|--------|
| SilentFallback | 5 | 2 | 3 | 0 |
| EmptyCatch | 8+ | 4 | 3 | 1 |
| CompatibilityBranch | 3 | 3 | 0 | 0 |
| SilentCorrection | 2 | 1 | 1 | 0 |
| DefensiveGuess | 3 | 1 | 2 | 0 |

Details:

- `RequestOverrideConfig.parsedHeaders` 无效 JSON -> `{}`：FailFast。
- Domain rules parse fail -> `[]`：FailFast 或至少 UI alert。
- Linux-like health fail -> Chaquopy：KeepWithAlert for ordinary scripts, FailFast for project/explicit Linux-like。
- Floating ball hide/update catch `_`：KeepWithAlert not needed，属于 best-effort UI 辅助。
- AppUpdate event numeric fallback：FailFast in debug/test，release 可显示错误事件。

## 17. Testing Authenticity Analysis

### Confidence Assessment

| Test Area | Real Confidence | Risk | Action |
|-----------|-----------------|------|--------|
| `script_name_validator_test.dart` / `project_path_validator_test.dart` | High | 低 | Keep |
| `services/http_inspector_store_test.dart` | Medium-High | widget singleton 仍有异常日志 | Keep + tighten |
| `services/update_service_test.dart` | Medium | 只覆盖 release parsing，不覆盖 checksum install policy | Expand |
| `download_engine_structure_test.dart` | Low | 字符串存在不代表行为可用 | Rewrite |
| `runtime_linux_like_native_bridge_test.dart` | Low | 大量源码 token 断言 | Rewrite gradually |
| Frontend source tests | Low-Medium | 防回退有用，但 refactor brittle | Replace with widget/behavior tests |

### Valuable Tests

- Validators：路径穿越、脚本名边界。
- Model/provider tests：脚本分组、置顶、最近顺序、project metadata。
- HTTP store tests：record round-trip、trim、flush/restore。
- Execution provider tests：日志裁剪、stale run status、fallback 当前行为。

### Suspicious Tests

- 读 `File(...).readAsStringSync()` 后 `contains(...)` 的结构测试。
- 大量 `isNot(contains(...))` 用于证明功能移除，容易被注释或重命名误导。
- UI 设计测试检查具体字符串/控件 token，重构成本高。

### Missing Tests

- 自动更新 checksum/signature 强制策略。
- Android APK 签名证书验证。
- Release APK post-process verify。
- Linux-like targetSdk 35+ 设备执行冒烟。
- Network debug global override 对更新检查的影响。

## 18. Type Safety Analysis

### Summary

| Subtype | Count | Critical | High | Medium | Low |
|---------|-------|----------|------|--------|-----|
| UnsafeBlock | 0 | 0 | 0 | 0 | 0 |
| TypeAssertion | 3 | 0 | 0 | 2 | 1 |
| InputBoundary | 4 | 0 | 1 | 2 | 1 |
| OutputLeak | 1 | 0 | 0 | 1 | 0 |
| BooleanTrap | 3 | 0 | 0 | 0 | 3 |
| StringlyTyped | 5+ | 0 | 0 | 3 | 2 |
| ErrorType | 4 | 0 | 0 | 2 | 2 |

Key points:

- MethodChannel method names、event keys、status strings、runtime ids 都是 stringly typed。
- Dart `jsonDecode(body) as Map<String, dynamic>` 对 GitHub API 响应形状依赖强。
- Kotlin `call.argument<String>(...) ?: ""` 会把缺失参数变成空字符串继续深入。
- 错误码是字符串散布在 Kotlin/Dart 间，缺少统一 enum/contract。

## 19. Frontend State Analysis

### Summary

| Subtype | Count | Affected Components |
|---------|-------|---------------------|
| ComponentSize | 3 | `ScriptListPage`, `SettingsPage`, `NetworkInspectorPage` |
| StateDuplication | 2 | settings/network filters |
| PropDrilling | 1 | main/settings callbacks |
| EffectChain | 3 | settings load/save, update dialog progress, network debug config |
| UIBusinessCoupling | 4 | script list actions, settings runtime install, update manager dialog, network export |
| DOMasState | 0 | Not applicable |
| RequestState | 2 | update check/download, package install |
| RenderPerf | 1 | large network body/image pages |

Notes:

- `IndexedStack` 和 cached themes 是正向性能选择。
- 页面巨型化已经超过“前端整理”层面，建议把业务 action 提取到 service/controller。
- 网络详情和图片预览需要按 body size 做更强 UI/内存保护。

## 20. Backend API Analysis

### Summary

| Subtype | Count | Affected Endpoints |
|---------|-------|--------------------|
| ApiConsistency | 2 | MethodChannel methods |
| Validation | 3 | update URL/checksum, request config, native args |
| Auth | 0 | No server auth surface |
| NplusOne | 0 | Not applicable |
| Caching | 1 | GitHub release / runtime manifest no stale cache mostly handled |
| ErrorResponse | 2 | string error codes, event fallback |
| BusinessLogic | 2 | UI-triggered update/runtime flows |
| DataFlow | 3 | APK update, project ZIP, HTTP inspector |

Notes:

- 这个项目没有传统后端 API；主要 API 边界是 MethodChannel、GitHub release、Python hook JSON。
- Linux-like manifest download 已显式 `Cache-Control: no-cache`，这是好点。
- MethodChannel 应按内部 backend API 对待，补 schema 和 contract。

## 21. Dependency Weight Analysis

### Dependency Scoreboard

| Dependency | Status | Weight | Transitives | Used For | Recommended Action |
|------------|--------|--------|-------------|----------|--------------------|
| Chaquopy pip bundle | Overweight | High | Many native wheels | Python batteries included | Split core/full profile |
| `file_picker@8.3.7` | Outdated | Medium | Platform plugins | File import/export | Plan major upgrade |
| `permission_handler@11.4.0` | Outdated | Medium | Platform plugins | Android permissions | Upgrade with targetSdk work |
| `flutter_lints@4.0.0` | Outdated | Low | lints | Code hygiene | Upgrade after fixing infos |
| `re_editor` path | Vendored | Medium | local third_party | Code editor | Track upstream changes manually |
| `isolate_contactor` transitive | Discontinued | Low-Medium | via dependency | isolate utilities | Track upstream replacement |

Notes:

- 不建议盲删科学计算/网络库，因为产品定位需要“开箱可用 Python”。
- 建议先做 APK size budget 和 runtime profile，而不是靠主观判断删依赖。

## 22. Code Consistency Analysis

| Area | Status | Finding |
|------|--------|---------|
| Dart lint | Mostly clean | 仅 8 个 deprecated info |
| Naming | Mostly readable | Stringly method/event keys 是一致性风险 |
| Error handling | Mixed | 有日志，但 silent fallback 分散 |
| File organization | Weak in hotspots | 大文件打破模块边界 |
| Tests | Inconsistent | 行为测试和源码字符串测试混用 |

## 23. Comment Coverage Analysis

| Area | Status | Notes |
|------|--------|-------|
| Complex build hack | Good but incomplete | 注释解释 proot/targetSdk/so stored 原因，但缺 verify 文档 |
| Runtime install | Adequate | 关键步骤有 progress 文案 |
| Security model | Missing | 没有集中说明更新信任链/权限/渠道 |
| README | Partially stale | 网络 hook 能力和 release checklist 不完整 |
| Inline comments | Mixed | 部分注释解释“为什么”，部分只是描述“做什么” |

## 24. Principles Compliance

当前代码库遵守了一些重要原则：外部路径输入有明确 validator；ZIP/rootfs 这类高风险输入有大小和路径保护；HTTP Inspector 和执行日志有资源上限；SQLite 查询普遍使用参数化 whereArgs；runtime 后端已经抽象出 Chaquopy/Linux-like。

主要违背原则集中在结构和失败语义：巨型文件违反 SRP 和文件大小纪律；更新 checksum 没有 fail-fast；请求配置 JSON 和 bridge event fallback 会隐藏错误；测试大量验证实现细节而不是行为。

### Principles Violated

| Principle | Violations | Severity | Affected Areas |
|-----------|------------|----------|----------------|
| Single Responsibility (1.1) | 4+ | Medium | Native bridge, major pages |
| File Size Limit (1.2) | 8 | Medium | `MainActivity.kt`, pages, runner |
| Low Coupling (2.1) | 3 | Medium | MethodChannel, Provider/UI/service |
| Fail-Fast (4.4) | 5 | High/Medium | Update, config, runtime fallback |
| Don't Swallow Errors (6.1) | 8+ | Medium | Config, persistence, UI helpers |
| Dependency Rule (7.1) | 2 | Medium | UI directly coordinating side effects |
| Test Behavior (8.1) | 6+ | Medium | Test suite |
| Least Privilege (4.6) | 3 | Medium | Manifest permissions/provider |

### Principles Respected

- 输入路径校验：`ScriptNameValidator` 和 `ProjectPathValidator`。
- 归档安全：项目 ZIP 导入有 entries、per-entry、total bytes 限制。
- 供应链局部防护：Linux-like runtime archive 有 SHA-256 校验。
- 资源上限：HTTP records、captured body bytes、执行日志/history 有 cap。
- 参数化数据库查询：SQLite whereArgs 使用较规范。
- Runtime 抽象：Dart 层已有 `RuntimeBackend`/`RuntimeManager`。

## 25. Fallback / Defensive Code Analysis

### Fallback Summary

| Subtype | Count | KeepWithAlert | FailFast | Remove |
|---------|-------|---------------|----------|--------|
| SilentFallback | 5 | 2 | 3 | 0 |
| EmptyCatch | 8+ | 4 | 3 | 1 |
| CompatibilityBranch | 3 | 3 | 0 | 0 |
| SilentCorrection | 2 | 1 | 1 | 0 |
| DefensiveGuess | 3 | 1 | 2 | 0 |

Recommended fallback policy:

- Keep: 悬浮球 hide/update、日志 best-effort、Android 版本兼容分支。
- KeepWithAlert: 普通脚本 runtime fallback、network debug global override。
- FailFast: APK checksum 缺失、请求配置 JSON 无效、项目型脚本 Linux-like 不可用、MethodChannel 安全敏感参数缺失。
- Remove: 测试环境中吞掉持久化插件异常。

## 26. Testing Authenticity Analysis

### Confidence Assessment

| Test Area | Real Confidence | Risk | Action |
|-----------|-----------------|------|--------|
| Validators | High | 低 | Keep |
| Providers/models | Medium-High | 中低 | Keep |
| HTTP store | Medium | 插件异常被吞 | Tighten |
| Update service | Medium | 缺完整更新链行为 | Expand |
| Native bridge structure tests | Low | 字符串断言假阳性 | Rewrite |
| Frontend source tests | Low-Medium | Refactor brittle | Replace gradually |

### Valuable Tests

- `script_name_validator_test.dart`
- `project_path_validator_test.dart`
- `script_project_provider_test.dart`
- `execution_provider_optimization_test.dart`
- `services/http_inspector_store_test.dart`
- `services/update_service_test.dart`

### Suspicious Tests

- `download_engine_structure_test.dart`
- `runtime_linux_like_native_bridge_test.dart`
- `editor_frontend_test.dart`
- `package_manager_frontend_test.dart`
- `network_frontend_test.dart`
- `frontend_design_system_test.dart`
- 大部分 `ui_theme_cleanup_test.dart`

### Missing Tests

- APK digest/signature verification.
- Release build artifact verification.
- TargetSdk policy check.
- Native MethodChannel contract tests.
- Linux-like device smoke on target 35+.

## 27. Type Safety Analysis

### Summary

| Subtype | Count | Critical | High | Medium | Low |
|---------|-------|----------|------|--------|-----|
| UnsafeBlock | 0 | 0 | 0 | 0 | 0 |
| TypeAssertion | 3 | 0 | 0 | 2 | 1 |
| InputBoundary | 4 | 0 | 1 | 2 | 1 |
| OutputLeak | 1 | 0 | 0 | 1 | 0 |
| BooleanTrap | 3 | 0 | 0 | 0 | 3 |
| StringlyTyped | 5+ | 0 | 0 | 3 | 2 |
| ErrorType | 4 | 0 | 0 | 2 | 2 |

Priority:

1. Typed update metadata including digest.
2. Typed MethodChannel schema.
3. Runtime backend enum/capability object instead of raw strings.
4. Structured error codes shared between Dart/Kotlin。

## 28. Frontend State Analysis

### Summary

| Subtype | Count | Affected Components |
|---------|-------|---------------------|
| ComponentSize | 3 | ScriptList, Settings, NetworkInspector |
| StateDuplication | 2 | settings/network |
| PropDrilling | 1 | theme/settings callbacks |
| EffectChain | 3 | settings/update/network |
| UIBusinessCoupling | 4 | script actions, runtime install, update dialog, export |
| DOMasState | 0 | N/A |
| RequestState | 2 | update/package |
| RenderPerf | 1 | body/image detail |

Minimal frontend refactor order:

1. Extract update dialog state/controller from `AppUpdateManager`.
2. Extract settings sections into widgets with injected actions.
3. Extract script list action service from view.
4. Extract network body preview widgets and size policies.

## 29. Backend API Analysis

### Summary

| Subtype | Count | Affected Endpoints |
|---------|-------|--------------------|
| ApiConsistency | 2 | MethodChannel |
| Validation | 3 | update/config/native args |
| Auth | 0 | N/A |
| NplusOne | 0 | N/A |
| Caching | 1 | release/runtime downloads |
| ErrorResponse | 2 | bridge/event errors |
| BusinessLogic | 2 | update/runtime |
| DataFlow | 3 | APK/project/http records |

Recommended API contract:

- `StartApkDownloadRequest { url, fileName, version, sha256 }` with `sha256` required for update-origin calls.
- `DownloadProgressEvent` typed fields with no silent numeric fallback in debug/test.
- `RuntimeExecutionRequest` with `requiredBackend`, `allowFallback`, `capabilities`.

## 30. Dependency Weight Analysis

### Dependency Scoreboard

| Dependency | Status | Weight | Transitives | Used For | Recommended Action |
|------------|--------|--------|-------------|----------|--------------------|
| Chaquopy pip bundle | Overweight | High | Many | Built-in Python packages | Split profiles |
| `file_picker@8.3.7` | Outdated | Medium | Several | File picking | Upgrade plan |
| `permission_handler@11.4.0` | Outdated | Medium | Several | Permissions | Upgrade with targetSdk |
| `flutter_lints@4.0.0` | Outdated | Low | `lints@4` | Linting | Upgrade |
| `re_editor` local path | Vendored | Medium | Local | Editor | Track upstream |
| `isolate_contactor` | Discontinued transitive | Low | via deps | Isolate support | Track replacement |

## 31. Recommended Fix Order

### Fix Immediately

| Priority | Issue | Why |
|----------|-------|-----|
| P0 | F1 APK 更新 digest/signature | 自动更新供应链风险 |
| P0 | F2 targetSdk release strategy | 当前公开发布阻断 |
| P1 | F3 release manifest 权限/flavor | 上架和安全审查风险 |
| P1 | F7 image body cap | 可快速降低 OOM 风险 |

### Fix Before Stable Release

| Priority | Issue | Why |
|----------|-------|-----|
| P1 | F10/F12 CI 与 release verify | 防止本地遗漏 |
| P1 | F14 MethodChannel contract | 防止跨语言参数裂缝 |
| P1 | F6 测试真实性 | 提升 release 信心 |
| P2 | F8/F9 fallback policy | 让错误可诊断 |
| P2 | F11 APK size budget | 降低更新失败率 |

### Schedule Later

| Priority | Issue | Why |
|----------|-------|-----|
| P2 | F5 分阶段拆大文件 | 降低长期回归成本 |
| P2 | F13 DB rollback strategy | 发布回滚安全 |
| P3 | F12 文档完善 | 降低交接成本 |
| P3 | F17 Radio API 迁移 | 保持 Flutter 升级余量 |

### Ignore for Now

| Issue | Reason |
|-------|--------|
| 悬浮球 best-effort catch | 辅助 UI，吞错风险低 |
| 部分源码结构测试 | 可短期保留作迁移护栏，但不要作为真实信心来源 |

## 32. Quick Wins

| Task | Value | Effort |
|------|-------|--------|
| image/* body cap 改为 1-2MB 并标记 truncated | 降低 OOM 风险 | 2-4 小时 |
| 无 checksum 时禁止自动更新安装 | 关闭最大供应链缺口的一半 | 4-8 小时 |
| `flutter analyze` Radio deprecated 修复 | 清理 release 噪音 | 1-2 小时 |
| 添加 CI analyze/test workflow | 防止未跑测试合并 | 2-4 小时 |
| Gradle post-process 后运行 `apksigner verify` | 避免坏 APK 出包 | 2-4 小时 |
| README 增加 release checklist | 降低误发布 | 2-4 小时 |
| Request headers 保存前 JSON 校验 | 避免静默配置丢失 | 3-6 小时 |

## 33. Long-term Refactor Plan

1. Update trust chain hardening

Motivation: 自动更新是最高风险供应链入口。

Approach: Release manifest/checksum -> Dart parse -> NativeBridge required sha256 -> Download verify -> APK signing cert pin -> installer。缺任何一步都禁止自动安装。

Risk: 旧 release 没有 checksum 会无法自动更新，需要过渡策略。

Testing strategy: Fake release JSON、fake bridge、Android signature verify test、release artifact CI。

2. Android channel/flavor separation

Motivation: Play 合规和 advanced proot 能力存在天然冲突。

Approach: `playRelease`、`advancedRelease`、`debug` flavor 分开 targetSdk、permissions、provider、更新策略和 UI 能力。

Risk: 多渠道维护成本上升。

Testing strategy: Manifest snapshot、targetSdk policy check、每个 flavor 至少构建一次。

3. Native bridge decomposition

Motivation: `MainActivity.kt` 过大，所有能力耦合在一个 class。

Approach: 先不改 behavior，把 handlers 拆到独立类；再引入 typed request/result；最后按能力补 JVM/instrumentation tests。

Risk: MethodChannel method name 或 error code 兼容性断裂。

Testing strategy: Contract tests freeze method names、required args、error codes、event payload。

4. Test suite authenticity upgrade

Motivation: 全绿测试目前不能覆盖最危险路径。

Approach: 保留少量结构 smoke，逐步用行为测试替换；优先更新、runtime、project ZIP、HTTP body cap、permissions。

Risk: 初期测试编写成本高。

Testing strategy: 每替换一个源码字符串测试，新增一个真实行为测试并删除对应 token 断言。

5. Runtime/package weight profiles

Motivation: APK 体积和更新成本会随着 Python 依赖继续增长。

Approach: 定义 lite/full runtime profile；核心包内置，可选包按需下载并校验；CI 记录 APK size trend。

Risk: 首次使用体验可能多一步下载。

Testing strategy: Size budget CI、首次安装包下载校验、弱网更新测试。

---

Verification performed:

- `flutter --version`: Flutter 3.44.0 stable, Dart 3.12.0。
- `flutter analyze`: 8 info，均为 `settings_page.dart` deprecated `Radio` API。
- `flutter test`: 131 tests passed；测试期间出现 `HttpInspectorStore.persist error: MissingPluginException(...)` 日志。
- `flutter pub outdated`: 5 个依赖受 pubspec 约束停留旧主版本；`isolate_contactor` transitive discontinued。
- Git worktree before report: existing user changes in `lib/main.dart`, `lib/pages/script_list_page.dart`, `lib/pages/settings_page.dart`, `lib/ui/app_theme_palette.dart`, `lib/ui/app_toolbars.dart`。
