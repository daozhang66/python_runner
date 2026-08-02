[中文](./README.md) | [English](./README_en.md)

# Python Runner

> Developed with **Claude Code/Codex** (AI coding assistant)

Python Runner is a Flutter-based Android app for running Python scripts with script management, full-screen terminal output, package management, network request inspection, and dual runtime support.

## Features

- **Script management**
  - Create, edit, rename, copy, import, export, and delete scripts
  - List / grid view
  - Long-press actions and multi-select batch operations
  - Pinned scripts support
  - Regular groups and Linux-like project groups

- **Project script groups**
  - Available only with the Linux-like runtime
  - Create an empty project with a default `main.py`
  - Import projects from ZIP files and let the user confirm or choose the main file
  - Browse, edit, rename, and delete files or folders inside a project
  - Run with the project root as the working directory, making project-local modules and resources easy to import

- **Code editor**
  - Syntax highlighting
  - Search and match navigation
  - Read-only / edit mode toggle
  - Font size adjustment
  - Save and run directly

- **Full-screen terminal**
  - Real-time stdout / stderr
  - `input()` support
  - Log search, error-only filter, copy, clear
  - Execution timeout control

- **Package manager**
  - Install / uninstall Python packages
  - Optional version pinning
  - Custom PyPI index support, leave empty to use the official source
  - Separate user-installed and built-in package lists
  - User-installed list shows top-level packages only
  - Uninstall can clean orphan dependencies

- **Dual runtime**
  - **Chaquopy**
    - Lightweight and stable
    - Good for standard Python scripts
  - **Linux-like**
    - Debian + proot environment
    - Better compatibility with packages needing system dependencies
    - Runtime installation required before first use

- **Network debugging**
  - Python HTTP request viewer
  - URL / domain search
  - Domain / method / status filtering
  - Request detail and JSON tree viewer
  - Global UA / header / cookie / timeout / redirect overrides

- **Logs and diagnostics**
  - App logs retain the latest 500 entries across restarts and support viewing, export, and clear
  - Cleared app logs cannot be recovered
  - Crash log and script error log capture
  - Diagnostic export

## Runtime notes

### Chaquopy

- Bundled inside the APK
- Best for lightweight scripts and common Python packages
- Some native-extension or system-level packages may not be supported

### Linux-like

- Based on Debian rootfs + proot
- Supports regular scripts and project script groups
- Project execution adds the project root and the main file directory to Python's search path, so project-local modules can be imported directly
- ZIP imports scan `.py` files and recommend main-file candidates, but the final main file must be confirmed or selected by the user
- Runtime files are installed under:

```text
/data/user/0/com.daozhang.py/files/linux_like/
```

- User-installed package directory:

```text
/data/user/0/com.daozhang.py/files/linux_like/user_site_packages
```

- The package manager only shows top-level user packages there, not auto-installed dependencies such as `certifi` or `urllib3`

## Package management

- **PyPI source**
  - You can set a custom pip index URL
  - Leave it empty to use the official source
  - The settings page can restore the official source with one tap

- **Install**
  - Install by package name
  - Optional version pinning
  - Chaquopy and Linux-like package environments are isolated from each other

- **Uninstall**
  - Removing a top-level package can also remove orphaned dependencies

## Network debugging

The request inspector automatically records common Python HTTP libraries:

- `requests`
- `httpx`
- `urllib` / `urllib3`
- `aiohttp`
- `socket` (DNS and connect)
- `subprocess` (command recording only, not interception)

It supports:

- Request summary
- URL search
- Request detail view
- JSON tree viewer
- Request override configuration
- Response body limits: images up to 30 MB, text / JSON defaults to 10 MB, audio / video records metadata only

Request overrides apply to scripts started after the configuration is saved. They support global User-Agent, Cookie, JSON Headers, a default timeout, redirect handling, and the configured network-debug proxy. Domain rules accept `example.com` and `*.example.com`; rules are evaluated in list order and the first match overrides global fields with the same name. Configurations can be copied for export or pasted for import.

## Project structure

```text
lib/
├─ main.dart
├─ models/
├─ pages/
├─ providers/
├─ runtime/
├─ services/
├─ utils/
└─ widgets/

android/
assets/
test/
```
