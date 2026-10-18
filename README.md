<p align="center">
  <img src="ClipKeeper/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="ClipKeeper 图标">
</p>

<h1 align="center">ClipKeeper</h1>

<p align="center">
  一个常驻 macOS 菜单栏的剪贴板历史工具。<br>
  复制过的文本、图片、文件都会被记下来，按 <kbd>⇧</kbd><kbd>⌘</kbd><kbd>V</kbd> 随时找回并粘贴。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5-orange" alt="Swift 5">
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-informational" alt="SwiftUI + AppKit">
  <img src="https://img.shields.io/badge/version-0.1.3-brightgreen" alt="版本 0.1.3">
</p>

---

<p align="center">
  <img src="docs/screenshots/panel.png" width="560" alt="ClipKeeper 剪贴板历史面板">
</p>

## 📸 截图

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/search.png" alt="搜索剪贴板历史"><br><sub>点一下搜索框即可搜索</sub></td>
    <td align="center"><img src="docs/screenshots/menu.png" alt="菜单栏菜单"><br><sub>菜单栏菜单：最近的记录和常用操作</sub></td>
  </tr>
  <tr>
    <td align="center" colspan="2"><img src="docs/screenshots/preview.png" alt="预览完整内容"><br><sub>按空格预览完整内容：长文本、大图、文件列表</sub></td>
  </tr>
  <tr>
    <td align="center" colspan="2"><img src="docs/screenshots/settings.png" width="480" alt="设置窗口"><br><sub>设置：开机自启、自定义快捷键、面板位置、自动粘贴、检查更新等</sub></td>
  </tr>
</table>

## ✨ 功能

- **自动记录**：文本、图片、文件（在访达中复制的）都会保存下来，重复内容自动去重
- **随叫随到**：全局快捷键在鼠标旁边弹出浮动面板，点一下搜索框就能搜索；快捷键可以自己录制
- **图片预览**：复制的图片（包括在访达里复制的图片文件）直接在列表里显示预览图
- **大预览**：按空格（或 ⌘Y、右键「预览」）在旁边弹出大预览，查看长文本的全部内容、大图和完整的文件列表
- **一键粘贴**：选中记录后自动粘贴到你正在使用的应用里
- **液态玻璃界面**：在 macOS 26 上使用系统的 Liquid Glass 风格，旧系统自动换成毛玻璃
- **随意摆放**：面板可以拖动、调整大小，会记住你上次的设置
- **置顶常用内容**：置顶的记录不会被自动清理
- **保护隐私**：自动忽略 1Password 等密码管理器复制的密码，也可以指定不记录某些应用；随时可以暂停记录
- **贴心设置**：开机自启、自定义快捷键、最多保存条数、面板出现位置
- **一键更新**：每天自动检查新版本，下载、安装、重新打开一步完成；升级后辅助功能授权会保留

## 💻 系统要求

- macOS 14 Sonoma 或更高版本（在 macOS 26 上体验最佳）
- 从源码编译需要 Xcode 26 或更高版本（用到了 macOS 26 SDK 中的液态玻璃 API；开发时使用的是 Xcode 27）

## 📦 下载安装

1. 在 [Releases 页面](https://github.com/sunnyoung0211/ClipKeeper/releases) 下载最新的 `ClipKeeper-x.y.z.dmg`
2. 打开 DMG，把 **ClipKeeper** 拖到旁边的「应用程序」文件夹
3. 打开「应用程序」里的 ClipKeeper

> [!NOTE]
> 这个应用暂时没有经过 Apple 公证，第一次打开时系统会提示"无法验证开发者"。请点「完成」关掉提示，然后打开
> **系统设置 → 隐私与安全性**，在最下面的「安全性」部分点 ClipKeeper 旁边的 **仍要打开**，输入电脑密码确认即可，以后就不会再提示了。
>
> 熟悉终端的话，也可以用这条命令代替：`xattr -dr com.apple.quarantine /Applications/ClipKeeper.app`

装好后，屏幕右上角的菜单栏会出现一个回形针图标，按 <kbd>⇧</kbd><kbd>⌘</kbd><kbd>V</kbd> 打开剪贴板历史。

**升级**：从 v0.1.2 开始，可以在「设置 → 更新」里点「检查更新」，发现新版本后点「下载并安装」，
ClipKeeper 会自动下载、替换并重新打开，不用再手动下载 DMG。从 v0.1.3 开始还会每天自动检查一次，
有新版本时菜单栏菜单的最上面会出现提示。（v0.1.1 需要手动下载安装一次新版本。）

> 从 v0.1.3 开始，每个版本都用同一张证书签名，升级后自动粘贴的授权会保留。
> 从 v0.1.2 或更早的版本升级到 v0.1.3 时，还需要最后一次重新授权：在「系统设置 → 隐私与安全性 → 辅助功能」里
> 选中 ClipKeeper，点 `−` 删掉，再重新打开 ClipKeeper 授权一次即可。

## 🚀 从源码编译

### 1. 获取代码

```bash
git clone https://github.com/sunnyoung0211/ClipKeeper.git
cd ClipKeeper
```

### 2. 配置代码签名（推荐，可跳过）

项目默认使用"临时签名"，clone 下来就能直接编译运行。但临时签名每次重新编译都会变，
自动粘贴需要的辅助功能授权会跟着失效（见下面的「[辅助功能权限](#-辅助功能权限)」），所以推荐换成你自己的开发者证书：

1. 打开 Xcode，菜单 `Xcode → Settings… → Accounts`，点左下角 `+` 登录你的 Apple ID（免费账号即可）
2. 在终端运行下面的命令查看你的团队 ID，输出里 `OU=` 后面那一串就是：
   ```bash
   security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
   ```
3. 把 `Config/Local.example.xcconfig` 复制一份，改名为 `Config/Local.xcconfig`，把里面的 `你的团队ID` 换成上一步查到的 ID

`Config/Local.xcconfig` 已被 `.gitignore` 忽略，你的团队 ID 不会被提交到仓库。

> [!WARNING]
> 不要在 Xcode 的 `Signing & Capabilities` 界面里直接选择 Team，那样 Xcode 会把团队 ID 写进项目文件，提交时就会被公开。

### 3. 运行

**用 Xcode（推荐，适合学习和调试）**：按 <kbd>⌘</kbd><kbd>R</kbd>。菜单栏右上角会出现 ClipKeeper 的图标；它不会出现在程序坞里，这是正常的。

**用命令行**：

```bash
./scripts/build.sh --run       # 编译并运行
./scripts/build.sh --install   # 编译并安装到"应用程序"文件夹（日常使用推荐）
```

## 📖 使用方法

### 面板快捷键

| 按键 | 作用 |
|---|---|
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>V</kbd> | 打开 / 关闭面板（可在设置里更换） |
| <kbd>↑</kbd> <kbd>↓</kbd> | 上下选择 |
| <kbd>↩</kbd> | 粘贴选中的记录 |
| <kbd>空格</kbd>（搜索框为空时）/ <kbd>⌘</kbd><kbd>Y</kbd> | 打开 / 关闭预览，上下选择时预览跟着切换 |
| <kbd>⌘</kbd><kbd>1</kbd> ~ <kbd>⌘</kbd><kbd>9</kbd> | 直接粘贴第 1 ~ 9 条 |
| <kbd>⌘</kbd><kbd>P</kbd> | 置顶 / 取消置顶 |
| <kbd>⌘</kbd><kbd>⌫</kbd> | 删除 |
| <kbd>esc</kbd> | 关闭预览 / 关闭面板 |
| 单击 | 选中这条；再单击已选中的那条（或者双击）就粘贴 |
| 右键 | 更多操作：仅复制不粘贴、预览、置顶、删除 |

打开面板时搜索框不会自动获得焦点：**要搜索请先点一下搜索框**。没点搜索框时，除了上面这些快捷键，
其他按键（直接打字、<kbd>⌘</kbd><kbd>V</kbd> 等）都会关掉面板，并把按键交还给你原来在用的应用，就像面板没打开过一样。

### 更换呼出快捷键

在设置里点一下「呼出快捷键」右边的按键框，然后直接按下想要的组合（比如 <kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd>）就保存好了，按 <kbd>esc</kbd> 取消。
旁边的 ↺ 按钮可以恢复默认的 <kbd>⇧</kbd><kbd>⌘</kbd><kbd>V</kbd>。

为了不影响日常使用，下面这些组合不能用，录制时会提示原因：

- 没有 <kbd>⌘</kbd>、<kbd>⌥</kbd>、<kbd>⌃</kbd> 中任何一个（<kbd>F1</kbd> ~ <kbd>F20</kbd> 除外，可以单独使用）
- 只用 <kbd>⌘</kbd>，比如 <kbd>⌘</kbd><kbd>C</kbd>：会和应用里的常用快捷键冲突
- 只用 <kbd>⌥</kbd> 或 <kbd>⌥</kbd><kbd>⇧</kbd>：这些组合是用来输入特殊字符的
- 已经是系统快捷键（「系统设置 → 键盘 → 键盘快捷键」里开启的），比如 <kbd>⌃</kbd><kbd>空格</kbd>

### 调整面板

- **移动**：拖动顶部搜索框周围或底部提示栏的空白处
- **调整大小**：拖动四条边或四个角（最小 300×260，最大 640×820）
- **出现位置**：在设置里选择「鼠标旁边」（默认）或「上次的位置」，也可以一键恢复默认大小

### 菜单栏菜单

点击菜单栏的回形针图标，可以看到最近 10 条记录，以及暂停记录、清空历史、打开设置等操作。暂停记录时，回形针右下角会出现暂停标记。

## 🔐 辅助功能权限

**自动粘贴**的原理是先把内容放进剪贴板，再模拟按下 <kbd>⌘</kbd><kbd>V</kbd>。macOS 要求你手动授权这项能力：

> 系统设置 → 隐私与安全性 → 辅助功能 → 打开 ClipKeeper

没有授权时，选中的内容只会复制到剪贴板，需要你自己按 <kbd>⌘</kbd><kbd>V</kbd>。设置窗口里会显示当前的授权状态。
（没点搜索框就打字时，把按键交还给原来的应用也要用到这项权限。）

> [!IMPORTANT]
> 使用临时签名（项目默认）时，签名**每次重新编译都会变**，macOS 会把它当成一个新应用，
> 于是会出现"系统设置里开关明明开着，却还提示需要授权"。按照上面「配置代码签名」换成你自己的开发者证书后，
> 签名就固定了，授权不会再失效。
>
> 如果已经遇到这个问题：在辅助功能列表里选中 ClipKeeper，点 `−` 删除，重新运行后再授权一次即可。

## 🛠 工作原理

### 一次"复制 → 粘贴"的完整流程

1. 你在任意应用里按下 <kbd>⌘</kbd><kbd>C</kbd>
2. `ClipboardMonitor` 每 0.5 秒检查一次剪贴板的 `changeCount`，发现变化就读取内容，生成一条 `ClipItem`
3. `ClipboardStore` 先去重，再保存到 SwiftData 数据库
4. 你按下 <kbd>⇧</kbd><kbd>⌘</kbd><kbd>V</kbd>，`HotkeyManager` 收到通知，`PanelController` 在鼠标旁边显示面板
5. 你选中一条并回车，`AppModel.paste()` 依次：关闭面板 → 写入剪贴板 → 模拟按下 <kbd>⌘</kbd><kbd>V</kbd>

### 几个值得一看的技术点

| 问题 | 做法 | 代码位置 |
|---|---|---|
| macOS 没有"剪贴板变化"通知 | 定时轮询 `NSPasteboard.changeCount`，开销极小 | `ClipboardMonitor` |
| 不能记录密码 | 跳过带有 `org.nspasteboard.ConcealedType` 等标记的内容 | `ClipboardMonitor` |
| 面板不能抢走当前应用的焦点 | 使用 `.nonactivatingPanel` 样式的 `NSPanel`，⌘V 才能粘贴到原来的应用 | `PanelController` |
| 全局快捷键 | 使用 Carbon 的 `RegisterEventHotKey`，不需要额外权限 | `HotkeyManager` |
| 录制快捷键 | 用 `NSEvent` 的本地监听在按键分发前截获组合键；录制期间暂停当前快捷键；用 `CopySymbolicHotKeys` 检查是否和系统快捷键重复 | `HotkeyRecorderView`、`Hotkey` |
| 列表里的图片预览 | 用 ImageIO 在后台线程直接解码出缩小的图片并缓存，几千像素的截图也不会卡 | `ClipboardStore` |
| 自动更新 | 查询 GitHub 最新 Release → 下载 DMG 并核对 SHA-256 → 挂载后取出应用，检查 Bundle ID、版本号和签名 → 替换当前应用并重新打开 | `UpdateService` |
| 升级后保留授权 | 发布版用固定的自签名证书签名，"签名要求"每个版本都一样，系统就认得是同一个应用；更新时还会检查新版本是不是同一张证书签的 | `setup-signing.sh`、`UpdateService` |
| 预览窗口不抢焦点 | 预览是一个不能成为焦点窗口的面板，键盘焦点一直留在历史面板上，上下键切换时预览跟着更新 | `PreviewPanelController` |
| 没点搜索框时打字 | 关掉面板，用 `CGEvent.postToPid` 把按键原样投递给原来的应用，紧接着打的字顺序也不会乱 | `PanelController` |
| 中文输入法打拼音时按回车 | 检测输入框里是否有"未确认的文字"，有就把按键留给输入法 | `PanelController` |
| 液态玻璃 + 圆角阴影 | 无边框透明窗口 + `NSGlassEffectView`；系统阴影会出现直角边框，所以自己画圆角阴影 | `PanelContainerView` |
| 打开访达 / 系统设置 | macOS 14 起切换前台是"协作式"的，要先 `yieldActivation` 让出前台 | `OpenHelper` |
| 同时运行多个实例会冲突 | 新启动的实例会让旧的退出 | `AppDelegate` |

### 项目结构

```
ClipKeeper/
├── ClipKeeperApp.swift          应用入口，定义菜单栏图标，保证只运行一个实例
├── AppModel.swift               "总管"：创建各模块并把它们连接起来  ← 建议从这里开始读
├── Models/
│   ├── ClipItem.swift           一条剪贴板记录（SwiftData 数据模型）
│   ├── Hotkey.swift             快捷键：显示、检查能不能用
│   └── AppSettings.swift        设置项（保存在 UserDefaults）
├── Services/
│   ├── ClipboardMonitor.swift   监听剪贴板，发现新内容就保存
│   ├── ClipboardStore.swift     历史数据的增删改查、去重、数量限制
│   ├── PasteService.swift       写回剪贴板 + 模拟 ⌘V 自动粘贴 + 权限引导
│   ├── HotkeyManager.swift      全局快捷键
│   ├── UpdateService.swift      检查更新、下载并安装新版本
│   └── OpenHelper.swift         打开访达 / 系统设置 / 网页
├── Views/
│   ├── MenuBarContentView.swift 菜单栏菜单
│   ├── PanelController.swift    浮动面板窗口：位置、大小、键盘操作
│   ├── PanelContainerView.swift 面板外壳：玻璃背景、阴影、拖边缩放
│   ├── PanelViewModel.swift     面板的状态和逻辑（搜索、选中、置顶…）
│   ├── HistoryPanelView.swift   面板界面：搜索框 + 列表 + 快捷键提示
│   ├── ClipRowView.swift        列表中的一行（图片显示预览图）
│   ├── PreviewPanelController.swift  按空格弹出的预览窗口：位置、大小
│   ├── ClipPreviewView.swift    预览窗口的内容：全文、大图、文件列表
│   ├── SettingsView.swift       设置窗口
│   ├── HotkeyRecorderView.swift 设置里的快捷键录制框
│   └── UpdateSection.swift      设置里的"更新"分组
├── Debug/
│   └── DemoData.swift           演示模式（只在 Debug 版本中编译，用来截图）
└── Assets.xcassets              App 图标、菜单栏图标

Config/
├── Base.xcconfig                签名的公共配置（默认临时签名）
└── Local.example.xcconfig       本地签名配置模板（复制为 Local.xcconfig 后填入团队 ID）

Design/
├── glass-clip-icons/            App 图标方案（当前使用 07b-glassclip-coral）
│   └── 07b-glassclip-coral/     SVG 源文件、各尺寸 PNG、.icns、Icon Composer 分层素材
└── menubar-icons-paperclip/     菜单栏图标方案（当前使用 tilted）
    └── tilted/                  正常 / 已暂停两种状态的模板图和 SVG 源文件
scripts/
├── build.sh                     命令行编译 / 安装
├── make-dmg.sh                  打包 DMG 安装包
├── setup-signing.sh             一次性设置发布用的固定签名
└── make-icons.swift             更新 App 图标（复制方案里的 PNG，或从 SVG 渲染）
```

**推荐的阅读顺序**：`AppModel` → `ClipboardMonitor` → `ClipboardStore` → `PasteService` → `PanelController` → 各个界面文件。代码里有详细的中文注释。

## 🧑‍💻 开发小贴士

- **打包安装包**：运行 `./scripts/make-dmg.sh`，会生成 `build/ClipKeeper-<版本号>.dmg`（通用版本，同时支持 Apple 芯片和 Intel 芯片）。
  为了不泄露个人信息，安装包里的应用会重新签名（开发证书里带有开发者的 Apple ID 邮箱），
  并去掉调试符号（里面记录了编译时的本机路径，包含用户名）。脚本最后会自动检查，发现个人信息就停止打包。
  发布新版本前，先在 Xcode 的 target 设置里修改 `Version`（MARKETING_VERSION）和 `Build`（CURRENT_PROJECT_VERSION）
- **固定签名**：在打包用的电脑上运行一次 `./scripts/setup-signing.sh`，会生成一张只用于代码签名、不含个人信息的证书
  （`ClipKeeper Code Signing`，放在登录钥匙串里），以后打包都用它签名，用户升级后辅助功能授权会保留。
  没设置时打包脚本会退回"临时签名"并给出提示。证书的备份在 `~/.clipkeeper-signing/`，**请备份到安全的地方，不要提交到 Git**：
  丢了只能重新生成（用户要重新授权一次，自动更新也会因为签名不一致而拒绝安装），泄露了别人就能冒充 ClipKeeper 签名
- **发布新版本**：在 GitHub 上新建 Release，标签用 `v` + 版本号（比如 `v0.1.3`，要和 `Version` 一致），并上传打包好的 DMG。
  已安装的用户在「设置 → 更新」里就能检查到它并一键安装。如果你 fork 了这个项目，记得把 `UpdateService.repository` 改成你自己的仓库
- **演示模式（用来截图）**：Debug 版本支持启动参数 `-DemoMode YES`，会使用一批示例数据（只在内存里，不读取也不修改真实的剪贴板历史），
  再配合 `-DemoOpen panel/settings/updates/menu`、`-DemoQuery 关键字`、`-DemoPreview 序号`、`-DemoBackdrop YES` 打开对应界面。详见 `ClipKeeper/Debug/DemoData.swift`
- **测试更新流程**：Debug 版本支持启动参数 `-UpdateFakeVersion 0.1.0`，假装当前是旧版本，这样就能在设置里看到"发现新版本"。
  注意：点「下载并安装」会把正在运行的这个应用（比如 Xcode 编译出来的）替换成 GitHub 上的发布版本
- **快速调试界面**：在 Xcode 的 `Product → Scheme → Edit Scheme… → Run → Arguments` 中添加启动参数 `-ShowPanelOnLaunch YES`，启动后会直接打开面板（只在 Debug 版本生效）
- **控制台里的系统日志**：`com.apple.linkd.autoShortcut`、`ViewBridge to RemoteViewService Terminated` 之类的信息是 macOS 系统框架输出的，不影响使用，可以忽略
- **设计方案的管理**：`Design/` 下的方案文件夹只会提交**正在使用**的那一个，其他方案只保留在本地（由 `.gitignore` 控制）。
  换用别的方案后，记得把 `.gitignore` 里对应的 `!` 那一行改成新方案的文件夹名
- **更换 App 图标**：图标方案放在 `Design/glass-clip-icons/`，每个方案文件夹里都有按尺寸单独渲染好的 PNG
  - 恢复成当前方案：`swift scripts/make-icons.swift`
  - 换成另一个方案：`swift scripts/make-icons.swift Design/glass-clip-icons/<方案文件夹>`
  - 也可以传入一个 SVG 来渲染，但系统自带的 SVG 解析不支持投影、整组模糊等效果，复杂图标请优先使用方案里现成的 PNG
  - 如果访达或系统设置里还显示旧图标，这是系统的图标缓存，重启一下应用即可
- **更换菜单栏图标**：把方案里的 `MenuBarIcon.imageset` 和 `MenuBarIconPaused.imageset` 两个文件夹复制到 `ClipKeeper/Assets.xcassets/`，覆盖原来的即可。
  它们是"模板图片"（只有黑色和透明度），系统会根据菜单栏深浅自动着色

## 💾 数据存储

所有数据只保存在本机，不会上传到任何地方：

```
~/Library/Application Support/ClipKeeper/
```

在设置里点「在访达中打开数据文件夹」可以直接打开它。删除这个文件夹就能清空所有数据。

## 🗺 路线图

- [ ] 保留富文本格式（目前按纯文本保存和粘贴），并支持"以纯文本粘贴"
- [ ] 按类型筛选（文本 / 图片 / 文件）
- [ ] 定时清理旧记录（比如自动删除 7 天前的记录）
- [ ] 用 Icon Composer 把图标升级为 macOS 26 分层图标（支持深色、染色外观；分层素材已在 `IconComposer/` 里准备好）
- [ ] 适配新版 macOS 的剪贴板隐私提示（如果系统询问是否允许 ClipKeeper 读取剪贴板，请选择允许）

## 📝 版本历史

### v0.1.3（2026-10-18）

- 按空格（或 ⌘Y、右键「预览」）在面板旁边弹出大预览：长文本的全部内容、大图、完整的文件列表
- 每天自动检查更新，发现新版本时菜单栏菜单里会提示
- 发布版改用固定的自签名证书签名，以后升级不用再重新授权辅助功能；自动更新时会检查新版本是不是同一张证书签的
- 单击记录改为先选中，再单击已选中的那条（或双击）才粘贴
- 打开面板时搜索框不再自动获得焦点：点一下才能搜索；没点搜索框时直接打字、按 ⌘V 等，会关掉面板并交还给原来的应用
- 去掉列表记录的鼠标悬停提示（已由预览代替）

### v0.1.2（2026-10-16）

- 支持自定义呼出快捷键：在设置里点一下按键框，直接按下新的组合即可
- 复制的图片（包括访达里复制的图片文件）在列表中直接显示预览图
- 支持在设置中检查更新，一键下载并安装新版本

### v0.1.1（2026-10-16）

第一个公开版本：
- 记录文本、图片、文件，去重、置顶、搜索、删除
- 全局快捷键在鼠标旁边呼出液态玻璃风格的浮动面板，支持键盘操作和自动粘贴
- 面板可拖动、可调整大小，位置和大小可记忆
- 隐私保护：忽略密码类内容、忽略指定应用、暂停记录
- 设置：开机自启、快捷键、最多保存条数、面板出现位置
- 玻璃回形针风格的 App 图标和菜单栏图标
- 提供 DMG 安装包（通用版本，支持 Apple 芯片和 Intel 芯片）
