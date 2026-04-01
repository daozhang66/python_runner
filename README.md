# Python 运行器

Android 端 Python 脚本运行环境，基于 Flutter + Chaquopy。

## 主要功能

- 代码编辑器（语法高亮、搜索、缩进）
- 本地运行 & 云端运行
- 交互式输入（input）支持
- 图形引擎（scene 模块，游戏/动画）
- pip 包管理（安装/卸载）
- 50+ 内置 Python 库
- 运行日志历史与导出
- 脚本导入/导出/批量管理

## 网络调试体系（v1.3.0）

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
- WebSocket（云端运行）
- CustomPaint（图形渲染）
- Python Monkey Patch（HTTP Hook）
