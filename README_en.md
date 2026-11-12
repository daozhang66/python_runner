<div align="center">

<img src=".github/assets/logo.png" width="96" alt="Python Runner"/>

# Python Runner

**Python script runner for Android — write, run, manage dependencies, and connect AI**

[![Release](https://img.shields.io/github/v/release/daozhang66/python_runner?color=2ea44f&label=release)](https://github.com/daozhang66/python_runner/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/daozhang66/python_runner/ci.yml?branch=main&label=CI)](https://github.com/daozhang66/python_runner/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-GPL--3.0--only-blue)](./LICENSE)
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
| 🖥️ | **Run console** | Live stdout / stderr, `input()` interaction, log search and error filtering |
| 💻 | **Terminals & SSH** | Local shell and SSH terminals, multiple session tabs, touch selection / copy / paste |
| 📚 | **Package manager** | pip install / uninstall, pinned versions, custom PyPI mirrors, orphan cleanup |
| ⚙️ | **Dual runtime** | Chaquopy for lightweight speed; Linux-like (Debian + proot) for compatibility |
| 🌐 | **Network inspector** | Automatically records Python HTTP requests with global request overrides |
| 🤖 | **MCP server** | External AI clients operate your scripts and terminals through MCP, with permission switches, a pause button and complete logs |
| 🩺 | **Logs & diagnostics** | App logs persist across restarts, crash and script error reports, one-tap export |
| 📜 | **Terminal / AI logs** | Terminal, AI chat and AI operations logs, compressed segments, Summary / Standard / Detailed, export and delete |

## 🤖 MCP Setup

Python Runner ships with a built-in MCP (Model Context Protocol) server, so external AI clients such as Claude Desktop or Cursor can operate the app through the standard MCP protocol:

- 📖 **Read & write scripts**: create scripts, read and modify code, save files
- ▶️ **Run**: execute scripts or project groups with interactive `input()` support
- 📦 **Packages**: query and install Python packages
- 🌐 **Network records**: inspect network requests made by your scripts
- 💻 **Terminals**: the AI can open a local terminal, send commands and read output; at a password prompt it does not guess but tells you to type it in the app (turn on the "Terminal" permission in the MCP settings; off by default)

Safety by design: **token authentication**, **permission switches for sensitive operations**, a **this-device-only switch**, **sensitive data redaction**, **passwords kept out of the logs** and a **persistent AI operations log** — you stay in control of every step.

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

## 🐍 Two Python Versions

Every release carries two APKs:

| APK | Python | Notes |
|---|---|---|
| `…-py3.11.apk` | 3.11 | The default |
| `…-py3.10.apk` | 3.10 | Can pip install the official SciPy / scikit-learn Android wheels |

In-app updates only offer the APK of the Python version you have installed, so an update never switches Python. Both share one signature and can be installed over each other.

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

Build the Python 3.10 variant:

```bash
PYRUNNER_PYTHON=3.10 flutter build apk --release --dart-define=PYRUNNER_PYTHON=3.10
```

Pushing a `v*` tag (it must match the version in `pubspec.yaml`) builds and publishes both APKs and their `.sha256` files; the release text comes from `release-notes/<tag>.md`.

## 📄 License

Code authored for Python Runner is licensed under the [GNU GPL version 3 only (GPL-3.0-only)](./LICENSE), Copyright © 2025–2026 daozhang66. See [NOTICE](./NOTICE) for the project grant and scope.

Third-party code, fonts, and runtime components retain their respective licenses and copyright notices. Merely running independently written Python scripts with this application does not, by itself, require those scripts to use the GPL. Earlier MIT-licensed releases retain their original grants.

Distributing a GPL-covered APK requires compliance with GPL section 6. For download releases, section 6(d) permits equivalent access to the complete Corresponding Source and build scripts matching that APK; an outdated tag or a moving branch alone is not a substitute.

> Developed with **Claude Code / Codex** (AI coding assistant)
