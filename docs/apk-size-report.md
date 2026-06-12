# APK 体积报告

生成方式：

```bash
flutter build apk --release
cd android
./gradlew reportReleaseApkSize
```

Gradle 会输出报告到：

```text
build/app/reports/apk-size/release-size.txt
```

## 预算

- 警告阈值：170MB
- 硬失败阈值：190MB

超过警告阈值时构建仍可完成，但需要在 release checklist 中说明原因。超过硬失败阈值时 `reportReleaseApkSize` 会失败。

## 当前主要来源

- Chaquopy Python 运行时与 pip 依赖。
- Linux-like runtime 原生库与 assets。
- Flutter assets、resources、dex 与其他 Android 打包内容。

## 最近一次 release 构建

- APK: `build/app/outputs/flutter-apk/app-release.apk`
- 总大小: 157.1MB
- 状态: 低于 170MB 警告阈值
- 报告: `build/app/reports/apk-size/release-size.txt`

分桶数据按 APK entry 原始大小统计，用于定位体积来源：

| 分组 | 大小 |
|------|------|
| native-libs | 84.2MB |
| chaquopy-python | 116.2MB |
| linux-like-assets | 0.0MB |
| flutter-assets | 0.4MB |
| resources | 1.6MB |
| dex | 14.3MB |
| other | 1.3MB |

## 后续优化方向

- 在独立 size probe 中评估 `minifyEnabled` 和 `shrinkResources`，确认不会破坏 Chaquopy、proot `.so` 存储方式或动态反射后再考虑进入 release。
- 审计 Chaquopy pip 依赖，把非核心科学计算/文档处理包改为可选下载或 runtime 内安装。
- 保持 release APK 中 proot 相关 `.so` 为 STORED，避免运行时执行权限问题。
