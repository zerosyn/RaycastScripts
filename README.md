# macOS Raycast 脚本集合

这是一个面向 macOS 的 [Raycast](https://www.raycast.com/) Script Command 集合，包含 Chrome 标签页侧边栏切换、向远程桌面输入剪贴板文本，以及 UniVPN 连接切换与状态验证。

## 功能概览

| Raycast 命令 | 功能 |
| --- | --- |
| **Toggle Chrome Sidebar** | 在 Chrome 中查找“展开标签页 / 收起标签页”按钮并自动点击，切换标签页侧边栏。支持中英文界面。 |
| **Paste to Remote Desktop** | 将 macOS 剪贴板中的文本，以模拟键盘输入的方式输入 Microsoft Remote Desktop 或 Windows App。 |
| **UniVPN Toggle** | 读取指定路由判断 UniVPN 当前状态，确认后通过菜单栏辅助功能切换连接，并等待路由实际变化。 |

这些命令使用 macOS Accessibility API，因此不依赖固定屏幕坐标，适用于不同的显示器和分辨率。

## 环境要求

- macOS 13 或更高版本
- [Raycast](https://www.raycast.com/)
- Xcode Command Line Tools：

  ```bash
  xcode-select --install
  ```

- 使用 Chrome 命令时需要 Google Chrome，并启用标签页侧边栏
- 使用远程桌面命令时需要 Microsoft Remote Desktop 或 Windows App
- 使用 UniVPN 命令时需要已安装 UniVPN

## 安装

1. 克隆仓库并进入目录：

   ```bash
   git clone https://github.com/RotulPlastik/ChromeSidebarToggleRaycast.git
   cd ChromeSidebarToggleRaycast
   ```

2. 编译 Swift 程序：

   ```bash
   ./build.sh
   ```

   编译结果会放到 `~/Documents/Raycast/`：

   - `toggle-chrome-sidebar`
   - `paste-to-remote-desktop`
   - `univpn-toggle`

3. 复制 Raycast wrapper：

   ```bash
   cp toggle-chrome-sidebar.sh paste-to-remote-desktop.sh univpn-toggle.sh ~/Documents/Raycast/
   ```

4. 在 Raycast 设置中，将 `~/Documents/Raycast/` 添加到 **Extensions → Script Commands → Add Directories**。

5. 在 macOS **系统设置 → 隐私与安全性 → 辅助功能** 中允许 Raycast。首次使用远程桌面输入时，macOS 可能还会请求自动化/System Events 权限。

## 使用方法

### Toggle Chrome Sidebar

在 Raycast 中运行 **Toggle Chrome Sidebar**，或为它设置快捷键。

程序会：

1. 通过 bundle identifier 找到正在运行的 Chrome。
2. 遍历 Chrome 的 Accessibility tree。
3. 查找标题或描述为以下内容的按钮：`Expand tabs`、`Collapse tabs`、`展开标签页`、`收起标签页`、`折叠标签页`。
4. 调用 Accessibility API 按下按钮。

### Paste to Remote Desktop

先在 macOS 上复制文本，将光标放到远程 Windows 会话的输入框中，然后运行 **Paste to Remote Desktop**。

它不会使用 RDP 剪贴板重定向，而是：

1. 读取 macOS 剪贴板文本。
2. 查找并激活 Microsoft Remote Desktop 或 Windows App。
3. 将不换行空格等特殊空格转换为普通空格。
4. 通过 System Events 将文本逐字符模拟输入。

这种方式适合远程环境禁用剪贴板粘贴的情况，但长文本输入会比系统粘贴慢。

### UniVPN Toggle

运行 **UniVPN Toggle** 后，程序会读取系统路由表中是否存在目标路由，判断当前是已连接还是未连接，并弹窗确认操作。确认后，它会：

1. 启动 UniVPN（如果尚未运行）。
2. 通过 Accessibility API 打开 UniVPN 菜单栏菜单。
3. 点击“连接”或“断开连接”。
4. 等待目标路由出现或消失，确认连接状态确实改变。

默认配置：

- UniVPN bundle identifier：`work.VPNClient`
- 用于判断连接状态的路由 IP：`192.168.11.254`

如环境不同，可在直接运行编译后二进制时覆盖：

```bash
UNIVPN_BUNDLE_ID="work.VPNClient" \
UNIVPN_ROUTE_IP="192.168.11.254" \
~/Documents/Raycast/univpn-toggle
```

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `toggle-chrome-sidebar.sh` | Raycast wrapper，声明命令名称和图标，并调用编译后的 Chrome 程序。 |
| `toggle-chrome-sidebar.swift` | Chrome 侧边栏切换的主逻辑。 |
| `paste-to-remote-desktop.sh` | Raycast wrapper，调用编译后的远程桌面输入程序。 |
| `paste-to-remote-desktop.swift` | 读取剪贴板、激活远程桌面应用并启动模拟键盘输入。 |
| `RemoteTypingCore.swift` | 远程桌面输入共享模块，负责特殊空格转换和 System Events AppleScript。 |
| `paste-to-remote-desktop-tests.swift` | 验证输入 AppleScript 内容和特殊空格转换逻辑的轻量测试。 |
| `univpn-toggle.sh` | Raycast wrapper，声明 UniVPN 命令并调用编译后的程序。 |
| `univpn-toggle.swift` | UniVPN 状态读取、确认、菜单操作、连接完成处理和路由验证。 |
| `build.sh` | 将 3 个 Swift 主程序编译到 `~/Documents/Raycast/`。 |

## 测试

测试文件不会被 `build.sh` 编译。可以单独运行：

```bash
swiftc RemoteTypingCore.swift paste-to-remote-desktop-tests.swift \
  -o /tmp/paste-to-remote-desktop-tests
/tmp/paste-to-remote-desktop-tests
```

修改 Swift 源码后，重新运行以下命令即可更新 Raycast 使用的二进制：

```bash
./build.sh
```

## 许可证

MIT
