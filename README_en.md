<div align="center">

<img src=".github/assets/logo.png" width="96" alt="Python Runner"/>

# Python Runner

**Python script runner for Android — write, run, manage dependencies, and connect AI**

[![Release](https://img.shields.io/github/v/release/daozhang66/python_runner?color=2ea44f&label=release)](https://github.com/daozhang66/python_runner/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/daozhang66/python_runner/ci.yml?branch=main&label=CI)](https://github.com/daozhang66/python_runner/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-MIT-blue)](./LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)](https://www.android.com)
[![Stars](https://img.shields.io/github/stars/daozhang66/python_runner?style=social)](https://github.com/daozhang66/python_runner/stargazers)

[中文](./README.md) | English

**[⬇️ Download latest](https://github.com/daozhang66/python_runner/releases/latest)** · [🤖 MCP setup](#-mcp-setup) · [🛠 Build from source](#-build-from-source)

</div>

---

## ✨ Features at a Glance

| | Feature | Description |
|---|---|---|
| 📝 | **Script management** | Create / edit / group / pin / batch actions, list & grid views |
| 📁 | **File manager** | Browse app and project directories, view, edit and save code with highlighting |
| 🖥️ | **Full-screen terminal** | Live stdout / stderr, `input()` interaction, log search and error filtering |
| 📚 | **Package manager** | pip install / uninstall, pinned versions, custom PyPI mirrors, orphan cleanup |
| ⚙️ | **Dual runtime** | Chaquopy for lightweight speed; Linux-like (Debian + proot) for compatibility |
| 🌐 | **Network inspector** | Automatically records Python HTTP requests with global request overrides |
| 🤖 | **MCP server** | External AI clients operate your scripts remotely through MCP |
| 🩺 | **Logs & diagnostics** | App logs persist across restarts, crash and script error reports, one-tap export |

## 🤖 MCP Setup

Python Runner ships with a built-in MCP (Model Context Protocol) server, so external AI clients such as Claude Desktop or Cursor can operate the app through the standard MCP protocol:

- 📖 **Read & write scripts**: create scripts, read and modify code, save files
- ▶️ **Run**: execute scripts or project groups with interactive `input()` support
- 📦 **Packages**: query and install Python packages
- 🌐 **Network records**: inspect network requests made by your scripts

Safety by design: **token authentication**, **confirmation for sensitive operations**, **sensitive data redaction**, and **full audit logging** — you stay in control of every step.

Enable the server in **Settings → MCP**, then add the following to your AI client configuration:

```json
{
  "mcpServers": {
    "python-runner": {
      "type": "http",
      "url": "http://<phone-ip>:37891/mcp",
      "headers": {
        "Authorization": "Bearer <token generated on the MCP settings page>"
      }
    }
  }
}
```

## 🚀 Getting Started

1. Download and install the latest APK from [Releases](https://github.com/daozhang66/python_runner/releases/latest)
2. Create a script and run it with the **Chaquopy** runtime — no setup required
3. Need heavier dependencies? Install the Linux-like environment (Debian + proot) under **Settings → Runtime**

## ⚙️ Dual Runtime

| | Chaquopy | Linux-like |
|---|---|---|
| Environment | Bundled in the APK, works out of the box | Debian rootfs + proot |
| Startup speed | ⚡ Fast | Slower, first-time environment install required |
| pip packages | Best for common pure-Python packages | Stronger compatibility, more system dependencies |
| Project script groups | — | ✅ In-project file browsing and module imports |

## 🌐 Network Inspector

Automatically records HTTP requests made through `requests`, `httpx`, `urllib`, `aiohttp`, `socket` and more, with URL / host search, request details, JSON tree views and summary statistics. Global overrides for UA / Cookie / Headers / timeout / redirect policy can be applied to your scripts.

## 🛠 Build from Source

```bash
git clone https://github.com/daozhang66/python_runner.git
cd python_runner
flutter pub get
flutter build apk --release
```

> Requires Flutter stable and the Android SDK. The APK is output to `build/app/outputs/flutter-apk/`.

## 📄 License

[MIT](./LICENSE) © 2025 daozhang66

> Developed with **Claude Code / Codex** (AI coding assistant)
