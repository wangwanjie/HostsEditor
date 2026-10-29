<p align="center">
  <img src="assets/icon-256.png" width="128" height="128" alt="HostsEditor 图标">
</p>

<h1 align="center">HostsEditor</h1>

<p align="center">
  macOS 上的 Hosts 文件编辑与方案切换工具：在多套 hosts 配置之间稳定切换，并通过特权 Helper 安全写回 <code>/etc/hosts</code>。
</p>

<p align="center">
  <a href="https://wangwanjie.github.io/HostsEditor/">主页</a> ·
  <a href="https://github.com/wangwanjie/HostsEditor/releases/latest">下载</a> ·
  <a href="https://github.com/wangwanjie/HostsEditor/issues">反馈</a>
</p>

![HostsEditor 主界面](assets/screenshots/home.png)

左侧是方案列表：「系统」为当前 `/etc/hosts` 全文，「默认」为剥离 HostsEditor 管理块后的基础内容，下方是本地方案与远程方案，勾选即启用；右侧是带语法高亮的编辑器。

## 下载

HostsEditor 为 Apple 芯片和 Intel 芯片分别提供安装包，需要 **macOS 13.0 或更高版本**。前往 [最新版本](https://github.com/wangwanjie/HostsEditor/releases/latest) 下载与你的 Mac 匹配的 DMG：

| 芯片 | 安装包 |
| --- | --- |
| Apple 芯片（M 系列） | `HostsEditor_V_<版本号>_arm64.dmg` |
| Intel 芯片 | `HostsEditor_V_<版本号>_x86_64.dmg` |

不确定是哪种芯片时，打开「苹果菜单 › 关于本机」，看「芯片」或「处理器」一栏。历史版本见 [Releases](https://github.com/wangwanjie/HostsEditor/releases)。

安装包均已通过 Apple 公证。打开 DMG，把 HostsEditor 拖进「应用程序」文件夹后打开即可。HostsEditor 内置自动更新（Sparkle），只会推送与本机芯片匹配的版本。

## 功能

- 多方案管理：创建多套本地 hosts 方案，按需启用、停用、复制或删除
- 系统级应用：将启用中的方案组合后写入系统 `/etc/hosts`，写入后自动刷新 DNS 缓存，立即生效
- 远程方案：从 http / https 地址拉取 hosts 内容保存为方案，支持手动刷新和按间隔自动刷新
- 导入导出：可把本地 hosts 文件导入为方案，也可把当前内容导出为文本文件
- 自动备份：每次写入系统 hosts 前自动备份旧内容（保留最近 30 份），可从「文件」菜单在访达中查看
- 菜单栏快速切换：通过状态栏图标快速启用或关闭方案
- 编辑器：注释、IP（含 IPv6）、主机名语法高亮，查找替换、批量注释（⌘/），支持浅色和深色外观
- 原始内容保留：保留系统 hosts 中不属于 HostsEditor 管理块的内容，写入前会重新读取，不会覆盖其他工具的修改
- 防误操作：有未保存修改时窗口关闭按钮显示提示点，退出前二次确认
- 多语言：简体中文、繁體中文、English
- 自动更新：集成 Sparkle，按架构分别推送更新

## 适用场景

- 本地开发时频繁切换测试环境 / 预发环境 / 线上环境
- 保存多套常用 hosts 配置，免去反复手动注释
- 团队内部通过 URL 分发一份共享 hosts 配置
- 从菜单栏快速开关某个 hosts 方案

## 工作方式

HostsEditor 只改写自己管理的部分。由应用管理的内容会写成带标记的块：

```text
# HostsEditor:BEGIN:<profile-id>
...
# HostsEditor:END:<profile-id>
```

这样既能把多个启用方案组合写入系统 hosts，也能保留不属于 HostsEditor 管理的原始基础内容。

界面中的几个关键项含义如下：

- `系统`：当前系统 `/etc/hosts` 的完整内容，可直接编辑并保存
- `默认`：从系统 hosts 中剥离掉 HostsEditor 管理块后的基础内容，只读查看
- `本地配置`：你手动维护的方案，可编辑、启用、删除
- `远程配置`：从 URL 拉取的方案，支持刷新

## 首次使用

1. 下载对应架构的 DMG，把 HostsEditor 拖入「应用程序」后打开
2. 首次读取或写入系统 hosts 时，应用会尝试注册特权 Helper
3. 如果系统要求授权，请输入管理员密码
4. 在较新的 macOS 上，如果出现“需要允许后台程序”，前往「系统设置 › 通用 › 登录项与扩展程序」，允许 HostsEditor 的后台程序后重新打开应用

## 使用说明

### 新建本地方案

1. 点击左下角 `新建`
2. 选择 `本地方案`
3. 编辑 hosts 内容
4. 点击 `保存并应用`

如果该方案已勾选启用，保存后会立即重新写入系统 hosts。

### 添加远程方案

1. 点击 `新建`
2. 选择 `远程方案`
3. 输入可访问的 URL
4. 应用会拉取内容并创建一个远程方案

远程方案支持手动 `刷新远程`，刷新后如果该方案当前处于启用状态，会自动重新写入系统 hosts。

### 远程方案自动刷新

在「偏好设置 → 通用 → 远程方案刷新」中可选择不自动刷新、每小时、每 6 小时或每天。远程内容有变化且方案处于启用状态时，会自动重新写入系统 hosts。

### 从菜单栏快速切换

应用启动后会在菜单栏显示图标。点击图标即可打开主窗口、查看所有方案、快速切换某个方案的启用状态或退出应用。

### 常用快捷键

| 快捷键 | 功能 |
| --- | --- |
| ⌘N / ⇧⌘N | 新建本地方案 / 新建远程方案 |
| ⌘O | 导入 hosts 文件为本地方案 |
| ⌘S | 保存并应用 |
| ⇧⌘S | 导出当前内容 |
| ⌘F / ⌘R | 查找 / 替换 |
| ⌘/ | 注释或取消注释选中行 |
| ⌘+ / ⌘- | 调整编辑器字号 |

## 权限与安全

编辑 `/etc/hosts` 需要管理员权限。HostsEditor 通过一个特权 Helper 完成实际读写：

- 主应用负责界面、方案管理、状态栏和远程拉取，本身不以 root 运行
- Helper 通过 `SMAppService` 注册为后台守护进程，主应用通过 XPC 与它通信
- 真正写入 `/etc/hosts` 的动作由 Helper 以高权限执行
- 首次安装或重新注册 Helper 时需要系统授权

## 常见问题

### 出现 “couldn’t communicate with a helper application”

通常是系统里残留了旧版本的后台任务记录。先退出 HostsEditor，然后在终端清理旧记录：

```bash
sudo launchctl bootout system/cn.vanjay.HostsEditor.Helper 2>/dev/null || true
sudo launchctl bootout system/cn.vanjay.HostsEditorHelper 2>/dev/null || true
```

确认 `/Applications`、`~/Applications` 里只有一份 `HostsEditor.app`，重新打开应用，点击一次“启用或修复后台帮助程序”，再触发一次系统 hosts 的读取或写入。

### 提示“需要允许后台程序”

前往「系统设置 › 通用 › 登录项与扩展程序」，允许 HostsEditor 的后台程序后，重新启动应用。

## 系统要求

- macOS 13.0 或更高版本
- Apple 芯片（arm64）或 Intel 芯片（x86_64）

## 反馈

遇到问题或有功能建议，欢迎在 [Issues](https://github.com/wangwanjie/HostsEditor/issues) 中反馈。本仓库只用于发布安装包与更新信息，不包含源代码。

## Star 趋势

[![Star History Chart](https://api.star-history.com/svg?repos=wangwanjie/HostsEditor&type=Date)](https://star-history.com/#wangwanjie/HostsEditor&Date)

Copyright © 2026 VanJay. All rights reserved.
