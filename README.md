[English](./README_en.md) | [中文](./README.md)

# Python Runner

> 本项目由 **Claude Code/Codex**辅助开发

一个基于 Flutter 的 Android Python 脚本运行器，提供脚本管理、全屏终端、库管理、网络请求调试，以及双运行时切换能力。

## 主要功能

- **脚本管理**
  - 新建、编辑、重命名、复制、导入、导出、删除
  - 列表/宫格双视图
  - 长按菜单与多选批量操作
  - 支持脚本置顶
  - 支持普通分组与 Linux-like 项目型脚本组

- **项目型脚本组**
  - 仅 Linux-like 引擎可用
  - 支持新建空项目，默认创建 `main.py`
  - 支持从 ZIP 导入项目，并由用户确认或选择主程序
  - 支持项目内文件/目录浏览、编辑、重命名、删除
  - 运行时项目根目录作为工作目录，方便脚本引用项目内模块和资源

- **代码编辑器**
  - 语法高亮
  - 搜索与跳转
  - 只读/编辑切换
  - 字号调节
  - 保存后直接运行

- **全屏终端**
  - 实时 stdout / stderr 输出
  - `input()` 交互输入
  - 日志搜索、错误过滤、复制、清空
  - 运行超时控制

- **悬浮球**
  - 运行状态指示
  - 自动贴边与自动收起
  - 最近脚本快捷运行
  - 拖拽到底部区域快速停止脚本

- **库管理**
  - 安装 / 卸载 Python 包
  - 支持指定版本
  - 支持自定义 PyPI 源，留空使用官方源
  - 用户安装 / 内置库分开展示
  - 用户安装列表只显示顶层包，不显示自动依赖
  - 卸载时支持清理孤儿依赖

- **双运行时**
  - **Chaquopy**
    - 轻量、稳定、启动快
    - 适合常规 Python 脚本
  - **Linux-like**
    - Debian + proot 环境
    - 支持更多系统依赖与 pip 包
    - 首次使用需在设置页安装运行环境

- **网络调试**
  - 底部「网络」页查看 Python HTTP 请求
  - 支持 URL / 域名搜索
  - 支持域名、方法、状态码筛选
  - 支持请求详情、JSON 树查看
  - 支持全局 UA / Header / Cookie / Timeout / Redirect 覆盖

- **日志与诊断**
  - 系统日志查看、导出、清空
  - 崩溃日志与脚本错误日志记录
  - 诊断信息导出

## 运行时说明

### Chaquopy

- 内置到 APK 中
- 适合轻量脚本与常用 Python 库
- 某些需要原生编译扩展或系统依赖的包可能无法安装

### Linux-like

- 基于 Debian rootfs + proot
- 支持普通脚本和项目型脚本组
- 项目运行时会把项目根目录和主程序所在目录加入 Python 搜索路径，项目内模块可直接按包/模块方式导入
- 导入 ZIP 项目时会扫描 `.py` 文件并推荐候选主程序，但最终主程序必须由用户确认或手动选择
- 运行环境首次安装后会解压到：

```text
/data/user/0/com.daozhang.py/files/linux_like/
```

- 用户安装包目录：

```text
/data/user/0/com.daozhang.py/files/linux_like/user_site_packages
```

- 库管理页中的“用户安装”只显示顶层安装包，不显示 `certifi`、`urllib3` 这类自动依赖

## 库管理说明

- **PyPI 源**
  - 可手动设置 pip 索引地址
  - 留空时使用官方源
  - 设置页支持一键恢复官方源

- **安装**
  - 可输入包名
  - 可选指定版本
  - Linux-like 与 Chaquopy 的包互相独立

- **卸载**
  - 卸载顶层包时，会尝试清理当前已无人依赖的孤儿依赖

## 网络调试说明

自动记录以下常见 Python HTTP 库请求：

- `requests`
- `httpx`
- `urllib` / `urllib3`
- `aiohttp`
- `socket` (DNS 和 connect)
- `subprocess` (仅记录命令，不拦截)

支持：

- 统计摘要
- URL 搜索
- 请求详情
- JSON 树状查看
- 请求覆盖配置
- 响应体大小限制（图片最大 30MB，文本/JSON 等默认 10MB，音视频仅记录 metadata）

## 项目结构

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
