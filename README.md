[中文文档](./README_zh.md) | [English](#readme)

# Python Runner

> Developed with **Claude Code** (Anthropic's AI coding assistant)
>
> 本项目由 Claude Code 辅助开发

A Flutter-based Python script runner with real-time console, package management, and network debugging capabilities.

## Features

- **Code Editor**: Syntax highlighting, search, indentation support
- **Run Locally & Remotely**: Local execution + cloud execution via WebSocket
- **Interactive Input**: Full `input()` support
- **Graphics Engine**: `scene` module for games and animations (CustomPaint)
- **Package Manager**: Install/uninstall pip packages
- **50+ Built-in Python Libraries**: Comprehensive standard library coverage
- **Execution History**: Log persistence and export
- **Script Management**: Import/export/batch operations

## Network Debugging System (v1.3.0)

Three-layer network debugging:

### 1. Proxy / SSL Debugging (External)
- Configure proxy host/port to export requests to Charles/Fiddler/Proxyman/Mitmproxy
- Allow insecure certificates for MITM tools
- Settings → Network Debug Mode

### 2. Network Request Viewer (Internal)
- Bottom "Network" tab for real-time HTTP request monitoring
- Shows: method, URL, headers, body, status, response headers/preview, latency, errors
- Filter by domain/method/status code
- Copy/export request records
- Auto-hooked libraries: `requests`, `httpx`, `urllib3`

### 3. Global Request Override (Internal Control)
- Global User-Agent override (bypass python-requests/2.x.x blocking)
- Global extra headers injection (JSON)
- Global Cookie injection
- Default HTTP timeout
- Follow redirects toggle
- Force proxy toggle
- Settings → Enable Request Override

## Tech Stack

- **Flutter** + Material 3
- **Chaquopy** (Python runtime for Android)
- **WebSocket** (cloud execution)
- **CustomPaint** (graphics rendering)
- **Python Monkey Patch** (HTTP hooking)

## Getting Started

### Prerequisites

- Flutter SDK (>=3.0)
- Android Studio / VS Code with Flutter extension
- Android device or emulator (API 21+)

### Installation

```bash
git clone https://github.com/daozhang66/python_runner.git
cd python_runner
flutter pub get
flutter run
```

### Build APK

```bash
flutter build apk --release
```

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── models/                      # Data models (execution_state, log_entry, etc.)
├── pages/                       # UI pages (console, editor, settings, etc.)
├── providers/                   # State management (Provider pattern)
├── services/                    # Core services (logger, database, bridge, etc.)
├── utils/                       # Utilities (ANSI parser, etc.)
└── widgets/                     # Reusable widgets
android/                         # Android native configuration
assets/                          # Static assets
test/                            # Unit tests
```

## Configuration

- **Python Environment**: Chaquopy automatically bundles Python 3.8+ with 50+ packages
- **Custom Libraries**: Place `.py` files in `assets/python/` or install via built-in pip
- **Network Debug**: Enable in Settings → Network Debug Mode

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

Distributed under the MIT License. See `LICENSE` for more information.

## Contact

Project Link: [https://github.com/daozhang66/python_runner](https://github.com/daozhang66/python_runner)
