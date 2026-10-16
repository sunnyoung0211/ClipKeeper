#if DEBUG
import AppKit

/// 演示模式：用一批示例数据展示界面，方便给 README 截图（只在 Debug 版本中编译）。
///
/// 演示模式下数据只放在内存里，不会读取、也不会修改你真实的剪贴板历史；
/// 也不会监听剪贴板、注册快捷键，或关掉正在运行的 ClipKeeper。
///
/// 用法：在启动参数里加上 `-DemoMode YES`，再按需加上：
/// - `-DemoOpen panel`      启动后打开浮动面板
/// - `-DemoOpen settings`   启动后打开设置窗口
/// - `-DemoOpen menu`       启动后打开菜单栏菜单
/// - `-DemoQuery 关键字`     打开面板后自动输入搜索词
/// - `-DemoBackdrop YES`    在面板 / 菜单后面垫一张彩色背景，让玻璃效果在截图里更明显，
///                          也避免截到屏幕上的其他内容
/// - `-DemoSettingsHeight 580`  设置窗口的高度（截图时让窗口刚好停在某个分组的结尾）
enum DemoData {
    /// 放入示例数据
    static func fill(_ store: ClipboardStore) {
        let now = Date()
        func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        func add(_ item: ClipItem, app: String, minutes: Double, pinned: Bool = false) {
            item.sourceAppName = app
            item.createdAt = minutesAgo(minutes)
            item.isPinned = pinned
            store.add(item)
        }
        func text(_ string: String) -> ClipItem {
            ClipItem(kind: .text, text: string, contentHash: "demo-text-" + string)
        }
        func files(_ names: [String]) -> ClipItem {
            let paths = names.map { demoFile(named: $0) }
            return ClipItem(kind: .file, text: names.joined(separator: "\n"), filePaths: paths,
                            contentHash: "demo-file-" + names.joined())
        }

        // 从旧到新依次加入（列表里新的排在前面）
        add(text("收到，我稍后处理，谢谢 🙏"), app: "微信", minutes: 60 * 26, pinned: true)
        add(files(["设计稿.png", "产品原型.key", "会议纪要.docx"]), app: "访达", minutes: 300)
        add(text("npm run build"), app: "终端", minutes: 180)
        add(text("ClipKeeper 是一个常驻 macOS 菜单栏的剪贴板历史工具，复制过的内容都会被记下来。"), app: "备忘录", minutes: 120)
        add(text("周五下午 3 点在 3 楼会议室开周会，记得带上电脑。"), app: "邮件", minutes: 64)
        add(text("let greeting = \"Hello, ClipKeeper!\""), app: "Xcode", minutes: 26)
        add(files(["季度报告.pdf"]), app: "访达", minutes: 15)
        if let image = demoImage() {
            add(image, app: "预览", minutes: 8)
        }
        add(text("https://developer.apple.com/documentation/swiftui"), app: "Safari", minutes: 3)
        add(text("git commit -m \"更换菜单栏图标\""), app: "终端", minutes: 1)
    }

    /// 按启动参数打开对应的窗口
    static func openRequestedWindows(app: AppModel) {
        let defaults = UserDefaults.standard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            switch defaults.string(forKey: "DemoOpen") {
            case "panel":
                app.showPanel()
                if let query = defaults.string(forKey: "DemoQuery") {
                    app.panelController.viewModel.query = query
                }
                if defaults.bool(forKey: "DemoBackdrop") {
                    placePanelOnBackdrop()
                }
            case "settings":
                app.showSettings()
            case "menu":
                if defaults.bool(forKey: "DemoBackdrop") {
                    placeMenuBackdrop()
                }
                // 菜单打开后会一直"占用"主线程直到关闭，所以放在最后、稍等背景画好再打开
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { openMenuBarMenu() }
            default:
                break
            }
        }
    }

    // MARK: - 示例文件和图片

    /// 在临时文件夹里建一个空文件，让列表能显示出对应类型的文件图标
    private static func demoFile(named name: String) -> String {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ClipKeeperDemo", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        return url.path
    }

    /// 画一张"日落"风格的示例图片
    private static func demoImage() -> ClipItem? {
        let size = NSSize(width: 1200, height: 800)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [
                NSColor(red: 0.98, green: 0.55, blue: 0.35, alpha: 1),
                NSColor(red: 0.93, green: 0.35, blue: 0.55, alpha: 1),
                NSColor(red: 0.45, green: 0.30, blue: 0.75, alpha: 1),
            ])?.draw(in: rect, angle: 90)
            NSColor(red: 1, green: 0.85, blue: 0.45, alpha: 0.95).setFill()
            NSBezierPath(ovalIn: NSRect(x: 450, y: 220, width: 300, height: 300)).fill()
            NSColor(red: 0.25, green: 0.18, blue: 0.45, alpha: 0.9).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1200, height: 260)).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return ClipItem(kind: .image, imageData: png, imageWidth: 1200, imageHeight: 800, contentHash: "demo-image")
    }

    // MARK: - 截图辅助

    /// 把面板挪到屏幕中间，并在它后面垫一张彩色背景（玻璃效果需要有东西在后面才看得出来）
    private static func placePanelOnBackdrop() {
        guard let panel = NSApp.windows.first(where: { $0 is FloatingPanel }),
              let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2,
                                     y: visible.midY - panel.frame.height / 2))

        let backdropFrame = panel.frame.insetBy(dx: -70, dy: -50)
        let backdrop = NSWindow(contentRect: backdropFrame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.level = NSWindow.Level(rawValue: panel.level.rawValue - 1)   // 紧贴在面板下面
        backdrop.isReleasedWhenClosed = false
        backdrop.contentView = DemoBackdropView(frame: NSRect(origin: .zero, size: backdropFrame.size))
        backdrop.orderFront(nil)
        demoBackdrop = backdrop
    }

    /// 在菜单栏图标下方垫一张彩色背景，顶部画一条只有 ClipKeeper 图标的"干净菜单栏"，
    /// 盖住真实的菜单栏，这样截图里不会出现其他应用的图标
    private static func placeMenuBackdrop() {
        guard let buttonWindow = findStatusBarButton(in: nil, searchAll: true)?.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let iconFrame = buttonWindow.frame                       // 菜单栏图标在屏幕上的位置
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        // 覆盖屏幕顶部整个宽度（菜单可能在图标的左边或右边展开）
        let height: CGFloat = 520
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height,
                           width: screen.frame.width, height: height)

        let backdrop = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)   // 盖住菜单栏，但在菜单下面
        backdrop.isReleasedWhenClosed = false
        let view = DemoBackdropView(frame: NSRect(origin: .zero, size: frame.size))
        view.menuBar = (height: menuBarHeight, iconCenterX: iconFrame.midX - frame.minX)
        backdrop.contentView = view
        backdrop.orderFront(nil)
        demoBackdrop = backdrop
    }

    private static var demoBackdrop: NSWindow?

    /// 用代码"点击"菜单栏图标，打开它的菜单
    private static func openMenuBarMenu() {
        findStatusBarButton(in: nil, searchAll: true)?.performClick(nil)
    }

    private static func findStatusBarButton(in view: NSView?, searchAll: Bool = false) -> NSStatusBarButton? {
        if searchAll {
            for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
                if let button = findStatusBarButton(in: window.contentView) { return button }
            }
            return nil
        }
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findStatusBarButton(in: subview) { return button }
        }
        return nil
    }
}

/// 截图用的彩色背景：几团柔和的色块，类似 macOS 的默认壁纸
private final class DemoBackdropView: NSView {
    /// 需要在顶部画"干净菜单栏"时设置：菜单栏高度、图标中心的 x 坐标
    var menuBar: (height: CGFloat, iconCenterX: CGFloat)?

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [
            NSColor(red: 0.36, green: 0.55, blue: 0.98, alpha: 1),
            NSColor(red: 0.62, green: 0.45, blue: 0.95, alpha: 1),
        ])?.draw(in: bounds, angle: -35)
        let blobs: [(NSRect, NSColor)] = [
            (NSRect(x: -60, y: bounds.height * 0.45, width: 360, height: 360), NSColor(red: 0.30, green: 0.85, blue: 0.95, alpha: 0.75)),
            (NSRect(x: bounds.width - 300, y: -80, width: 380, height: 380), NSColor(red: 1.0, green: 0.55, blue: 0.45, alpha: 0.8)),
            (NSRect(x: bounds.width * 0.35, y: bounds.height - 180, width: 280, height: 280), NSColor(red: 1.0, green: 0.80, blue: 0.40, alpha: 0.7)),
        ]
        for (rect, color) in blobs {
            NSGradient(starting: color, ending: color.withAlphaComponent(0))?
                .draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
        }
        drawMenuBar()
    }

    /// 画一条半透明的菜单栏，上面只有 ClipKeeper 的图标（处于"按下"状态）
    private func drawMenuBar() {
        guard let menuBar else { return }
        let bar = NSRect(x: 0, y: bounds.height - menuBar.height, width: bounds.width, height: menuBar.height)
        NSColor.white.withAlphaComponent(0.55).setFill()
        bar.fill()

        let highlight = NSRect(x: menuBar.iconCenterX - 18, y: bar.midY - 12, width: 36, height: 24)
        NSColor.black.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: highlight, xRadius: 12, yRadius: 12).fill()

        if let icon = NSImage(named: "MenuBarIcon") {
            let iconRect = NSRect(x: menuBar.iconCenterX - 9, y: bar.midY - 9, width: 18, height: 18)
            icon.draw(in: iconRect)
        }
    }
}
#endif
