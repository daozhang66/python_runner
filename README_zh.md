<div align="center">

<img src="android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png" width="96" alt="Python Runner"/>

# Python Runner

**Android 端 Python 脚本运行器 —— 写脚本、跑脚本、管依赖、连 AI**

[![Release](https://img.shields.io/github/v/release/daozhang66/python_runner?color=2ea44f&label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC)](https://github.com/daozhang66/python_runner/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/daozhang66/python_runner/ci.yml?branch=main&label=CI)](https://github.com/daozhang66/python_runner/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-MIT-blue)](./LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)](https://www.android.com)
[![Stars](https://img.shields.io/github/stars/daozhang66/python_runner?style=social)](https://github.com/daozhang66/python_runner/stargazers)

[English](./README.md) | 简体中文

**[⬇️ 下载最新版](https://github.com/daozhang66/python_runner/releases/latest)** · [🤖 MCP 接入](#-mcp-接入) · [🛠 从源码构建](#-从源码构建)

</div>

---

## ✨ 功能一览

| | 功能 | 说明 |
|---|---|---|
| 📝 | **脚本管理** | 新建 / 编辑 / 分组 / 置顶 / 批量操作，列表与宫格双视图 |
| 📁 | **文件管理** | 浏览应用与项目目录，高亮查看、编辑并保存代码文件 |
| 🖥️ | **全屏终端** | 实时 stdout / stderr，`input()` 交互，日志搜索与错误过滤 |
| 📚 | **库管理** | pip 安装 / 卸载、指定版本、自定义 PyPI 源、孤儿依赖清理 |
| ⚙️ | **双运行时** | Chaquopy 轻量快速；Linux-like（Debian + proot）兼容性更强 |
| 🌐 | **网络调试** | 自动记录 Python HTTP 请求，支持详情查看与全局请求覆盖 |
| 🤖 | **MCP 服务** | 外部 AI 通过 MCP 协议远程操作脚本，本机全程可控 |
| 🩺 | **日志诊断** | 应用日志跨重启保留，崩溃与脚本错误记录，一键导出 |

## 🤖 MCP 接入

Python Runner 内置 MCP（Model Context Protocol）服务器，Claude Desktop、Cursor 等外部 AI 客户端可以通过标准 MCP 协议直接操作 App：

- 📖 **读写脚本**：创建脚本、读取与修改代码、保存文件
- ▶️ **运行**：运行脚本或项目型脚本组，支持交互式 `input()`
- 📦 **装库**：查询与安装 Python 包
- 🌐 **网络记录**：查看脚本的网络请求记录

安全机制：**令牌鉴权**、**敏感操作二次确认**、**敏感信息脱敏**、**全程审计日志**，每一步都在你的掌控之中。

在应用的 **设置 → MCP** 中开启服务后，将以下配置加入你的 AI 客户端：

```json
{
  "mcpServers": {
    "python-runner": {
      "type": "http",
      "url": "http://<手机IP>:37891/mcp",
      "headers": {
        "Authorization": "Bearer <在 MCP 设置页生成的访问令牌>"
      }
    }
  }
}
```

## 🚀 快速开始

1. 从 [Releases](https://github.com/daozhang66/python_runner/releases/latest) 下载并安装 APK
2. 新建一个脚本，选择 **Chaquopy** 运行时，开箱即跑
3. 需要更复杂的依赖？到 **设置 → 运行环境** 安装 Linux-like 环境（Debian + proot）

## ⚙️ 双运行时

| | Chaquopy | Linux-like |
|---|---|---|
| 环境 | 内置于 APK，开箱即用 | Debian rootfs + proot |
| 启动速度 | ⚡ 快 | 稍慢，首次需安装环境 |
| pip 包 | 常用纯 Python 包为主 | 兼容性更强，支持更多系统依赖 |
| 项目型脚本组 | — | ✅ 支持项目内文件浏览与模块导入 |

## 🌐 网络调试

自动记录 `requests`、`httpx`、`urllib`、`aiohttp`、`socket` 等常见 Python HTTP 请求，支持 URL / 域名搜索、请求详情、JSON 树查看与统计摘要，还可为脚本配置全局 UA / Cookie / Header / 超时 / 重定向覆盖。

## 🛠 从源码构建

```bash
git clone https://github.com/daozhang66/python_runner.git
cd python_runner
flutter pub get
flutter build apk --release
```

> 需要 Flutter stable 与 Android SDK，APK 输出在 `build/app/outputs/flutter-apk/`。

## 📄 许可证

[MIT](./LICENSE) © 2025 daozhang66

> 本项目由 **Claude Code / Codex** 辅助开发
