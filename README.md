# HostsEditor

macOS 下的 Hosts 文件编辑与方案切换工具，纯 Swift + AppKit，最低支持 macOS 11.0。

## 功能

- **快速切换方案**：多套 hosts 方案，一键应用到系统 `/etc/hosts`
- **语法高亮**：注释、IP、主机名高亮（支持深色/浅色外观）
- **远程方案**：从 URL 拉取 hosts 配置并保存为方案，支持刷新
- **菜单栏**：状态栏图标可快速切换当前方案

## 权限说明

编辑系统 `/etc/hosts` 需要管理员权限，本应用通过 **SMJobBless** 安装一个“帮助程序”（Privileged Helper），由该帮助程序以 root 执行写入，主应用通过 XPC 与之通信。

- 首次使用“应用到系统”或“读取系统 hosts”时，如未安装帮助程序，会提示安装并请求管理员密码。
- 主应用已关闭 App Sandbox，以便安装 Helper 并与之通信。
- 若你修改了 Bundle ID 或使用不同的开发团队，需同步修改：
  - `HostsEditor/Info.plist` 中的 `SMPrivilegedExecutables`
  - `HostsEditorHelper/Info.plist` 中的 `SMAuthorizedClients`（将 `X6B6C6U6QV` 换成你的 Team ID）

## 构建与运行

1. 用 Xcode 打开 `HostsEditor.xcodeproj`
2. 选择 Scheme：**HostsEditor**，目标：**My Mac**
3. 若代码签名报错，在 Signing & Capabilities 中确认：
   - HostsEditor 与 HostsEditorHelper 的 **Team** 一致且有效
   - 使用“Sign to Run Locally”或你的开发证书
4. 运行（⌘R）

## 项目结构

- **HostsEditor/**：主应用（界面、方案管理、菜单栏、与 Helper 通信）
- **HostsEditorHelper/**：特权帮助程序（XPC 服务，读写 `/etc/hosts`）
- **HostsEditor/PrivilegedHelper/**：主应用中与 Helper 通信及安装逻辑
- **HostsEditor/Models/**：方案数据模型
- **HostsEditor/Services/**：HostsManager（方案 CRUD、应用、远程拉取）
- **HostsEditor/Views/**：语法高亮、编辑器、方案列表等 UI

## 依赖

- 无 SPM/CocoaPods 依赖，仅使用系统框架：AppKit、Foundation、ServiceManagement、Security、Combine。
