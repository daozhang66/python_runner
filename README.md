[English](./README_en.md) | [中文](./README.md)

# Python Runner

> 本项目由 **Claude Code**（Anthropic AI 编码助手）辅助开发

一个基于 Flutter 的 Python 脚本运行器，具备实时控制台、包管理器和网络调试功能。

## 主要功能

- **代码编辑器**：语法高亮、搜索、自动缩进
- **本地运行**：基于 Chaquopy 的本地执行
- **交互式输入**：完整支持 `input()` 函数
- **图形引擎**：`scene` 模块，支持游戏和动画（CustomPaint）
- **包管理器**：pip 包安装/卸载
- **50+ 内置 Python 库**：覆盖常用标准库
- **运行历史**：日志持久化与导出
- **脚本管理**：导入/导出/批量操作

## 网络调试体系

三层网络调试能力：

### 1. 代理 / SSL 调试（外部调试底座）
- 配置代理 host/port，将请求导出到 Charles/Fiddler/Proxyman/Mitmproxy
- 允许不安全证书，配合抓包工具的 MITM 证书
- 设置页 → 网络调试模式

### 2. 网络请求查看器（内部可视化）
- 底部「网络」Tab 实时查看所有 Python HTTP 请求
- 显示：请求方法、URL、请求头、请求体、状态码、响应头、响应体预览、耗时、错误类型
- 支持按域名/方法/状态码筛选
- 支持复制/导出请求记录
- 自动 Hook 的库：requests、httpx、urllib3

### 3. 全局请求覆盖（内部控制）
- 全局 User-Agent 覆盖（解决 python-requests/2.x.x 被拦截）
- 全局额外请求头注入（JSON 格式）
- 全局 Cookie 注入
- 默认 HTTP 超时控制
- 跟随重定向开关
- 强制代理开关
- 设置页 → 启用请求覆盖

## 技术栈

- Flutter + Material 3
- Chaquopy（Python 运行时）
- CustomPaint（图形渲染）
- Python Monkey Patch（HTTP Hook）

## 快速开始

### 环境要求

- Flutter SDK (>=3.0)
- Android Studio / VS Code with Flutter extension
- Android 设备或模拟器 (API 21+)

### 安装运行

```bash
git clone https://github.com/daozhang66/python_runner.git
cd python_runner
flutter pub get
flutter run
```

### 构建 APK

```bash
flutter build apk --release
```

## 项目结构

```
lib/
├── main.dart                    # App 入口
├── models/                      # 数据模型（execution_state、log_entry 等）
├── pages/                       # UI 页面（控制台、编辑器、设置等）
├── providers/                   # 状态管理（Provider 模式）
├── services/                    # 核心服务（日志、数据库、桥接等）
├── utils/                       # 工具类（ANSI 解析器等）
└── widgets/                     # 可复用组件
android/                         # Android 原生配置
assets/                          # 静态资源
test/                            # 单元测试
```

## 许可证

采用 MIT 许可证。详见 `LICENSE` 文件。

## 项目链接

- GitHub: [https://github.com/daozhang66/python_runner](https://github.com/daozhang66/python_runner)
