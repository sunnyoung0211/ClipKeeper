import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 自定义的浮动面板。
/// 无边框窗口默认不能成为"键盘焦点窗口"，重写这个属性后才能在搜索框里打字。
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// 没有任何控件处理的按键最后会送到窗口这里，默认会"嘟"一声，安静地忽略掉就好
    override func keyDown(with event: NSEvent) {}
}

/// 负责显示 / 隐藏浮动的历史面板、决定它的位置和大小，并处理键盘操作。
///
/// 为什么用 NSPanel 而不是普通窗口？
/// 带有 `.nonactivatingPanel` 样式的面板在显示时 **不会抢走当前应用的前台状态**。
/// 这样用户选中一条记录后，模拟的 ⌘V 才能粘贴到原来正在用的应用里（类似 Spotlight）。
final class PanelController: NSObject, NSWindowDelegate {
    let viewModel: PanelViewModel

    var onSelect: ((ClipItem) -> Void)? {
        didSet { viewModel.onSelect = onSelect }
    }
    var onCopyOnly: ((ClipItem) -> Void)? {
        didSet { viewModel.onCopyOnly = onCopyOnly }
    }

    // MARK: 尺寸（指的是玻璃面板本身，不含四周留给阴影的透明边距）
    static let defaultSize = NSSize(width: 340, height: 420)
    static let minSize = NSSize(width: 300, height: 260)
    static let maxSize = NSSize(width: 640, height: 820)
    static let cornerRadius: CGFloat = 20

    private let settings: AppSettings
    private let defaults = UserDefaults.standard
    private var panel: FloatingPanel?
    private var container: PanelContainerView?
    private var keyMonitor: Any?
    /// 按空格时在旁边显示完整内容的预览窗口
    private let preview: PreviewPanelController

    init(store: ClipboardStore, settings: AppSettings) {
        self.settings = settings
        viewModel = PanelViewModel(store: store, settings: settings)
        preview = PreviewPanelController(store: store)
        super.init()
        // 预览打开时，选中项变了就跟着换成新的那一条
        viewModel.onSelectionChanged = { [weak self] in self?.updatePreview() }
        viewModel.onPreview = { [weak self] _ in self?.showPreview() }
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        preview.hide()

        viewModel.reset()
        // 每次打开都换上一个新的界面，这样搜索框会被清空
        let hostingView = NSHostingView(rootView: HistoryPanelView(model: viewModel))
        hostingView.sizingOptions = []   // 窗口大小由我们自己控制，不让 SwiftUI 去改
        container?.setContent(hostingView)

        panel.setFrame(initialFrame(), display: false)
        panel.makeKeyAndOrderFront(nil)
        // 不让搜索框自动获得焦点（窗口自己当"焦点"）：用户点了搜索框才在里面输入，
        // 直接打字、按 ⌘V 等会关掉面板，交还给原来的应用（见 passToPreviousApp）
        panel.makeFirstResponder(nil)
        installKeyMonitor()
    }

    func hide() {
        preview.hide()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        removeKeyMonitor()
    }

    // MARK: - 预览

    /// 打开 / 关闭选中记录的预览
    func togglePreview() {
        preview.isVisible ? preview.hide() : showPreview()
    }

    func showPreview() {
        guard let item = viewModel.selectedItem, let anchor = glassScreenFrame else { return }
        preview.show(item, nextTo: anchor)
    }

    /// 预览窗口在屏幕上的位置（演示模式截图时用）
    var previewFrame: NSRect? {
        preview.frame
    }

    /// 选中项变了：预览开着的话换成新的那一条；没有选中项了就关掉
    private func updatePreview() {
        guard preview.isVisible else { return }
        if viewModel.selectedItem != nil {
            showPreview()
        } else {
            preview.hide()
        }
    }

    /// 玻璃面板在屏幕上的位置
    private var glassScreenFrame: NSRect? {
        guard let panel, let container else { return nil }
        return panel.convertToScreen(container.convert(container.glassFrame, to: nil))
    }

    /// 把面板恢复成默认大小，并忘掉上次的位置（设置里的"重置"按钮会调用）
    func resetSizeAndPosition() {
        defaults.removeObject(forKey: Keys.size)
        defaults.removeObject(forKey: Keys.origin)
    }

    // MARK: - NSWindowDelegate

    /// 用户点击了面板以外的地方 → 自动关闭
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// 窗口被拖动后，记住玻璃面板的位置（"上次的位置"模式会用到）
    func windowDidMove(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        let m = PanelContainerView.shadowMargins
        let glassOrigin = NSPoint(x: panel.frame.minX + m.left, y: panel.frame.minY + m.bottom)
        defaults.set(NSStringFromPoint(glassOrigin), forKey: Keys.origin)
        repositionPreview()
    }

    /// 拖动边缘改变大小时，预览窗口跟着移动
    func windowDidResize(_ notification: Notification) {
        repositionPreview()
    }

    /// 让预览窗口重新贴到面板旁边
    func repositionPreview() {
        if let anchor = glassScreenFrame {
            preview.reposition(nextTo: anchor)
        }
    }

    // MARK: - 创建窗口

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),   // 真正的大小在 show() 里设置
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 无边框 + 透明背景：窗口本身不画任何东西，外观完全由里面的圆角玻璃决定
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // 关掉系统阴影：系统会按整个矩形窗口画阴影，四个角会多出直角边框。
        // 阴影改由 PanelContainerView 按圆角形状自己画。
        panel.hasShadow = false

        panel.level = .floating          // 浮在普通窗口之上
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]  // 在所有桌面、全屏应用上都能显示
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let container = PanelContainerView(cornerRadius: Self.cornerRadius)
        container.minSize = Self.minSize
        container.maxSize = Self.maxSize
        container.onResizeEnded = { [weak self, weak container] in
            guard let self, let container else { return }
            // 保存玻璃面板的大小（不含阴影边距）
            self.defaults.set(NSStringFromSize(container.glassFrame.size), forKey: Keys.size)
        }
        container.onClickOutside = { [weak self] in
            self?.hide()
        }
        panel.contentView = container
        self.container = container
        return panel
    }

    // MARK: - 位置和大小

    /// 计算窗口打开时的位置和大小 = 玻璃面板的位置和大小，再向四周扩出阴影边距
    private func initialFrame() -> NSRect {
        let glass = initialGlassFrame()
        let m = PanelContainerView.shadowMargins
        return NSRect(
            x: glass.minX - m.left,
            y: glass.minY - m.bottom,
            width: glass.width + m.left + m.right,
            height: glass.height + m.top + m.bottom
        )
    }

    /// 计算玻璃面板打开时的位置和大小
    private func initialGlassFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: Self.maxSize)

        // 大小：用上次调整后的大小，但不能超过限制，也不能比屏幕还大
        var size = Self.defaultSize
        if let saved = defaults.string(forKey: Keys.size) {
            size = NSSizeFromString(saved)
        }
        size.width = min(max(size.width, Self.minSize.width), Self.maxSize.width, visible.width)
        size.height = min(max(size.height, Self.minSize.height), Self.maxSize.height, visible.height)

        // 位置："上次的位置"模式下，如果上次的位置还在某块屏幕上，就用它
        if settings.panelPlacement == .lastPosition, let saved = defaults.string(forKey: Keys.origin) {
            let frame = NSRect(origin: NSPointFromString(saved), size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                return frame
            }
        }
        return NSRect(origin: originNearMouse(mouse, size: size, visible: visible), size: size)
    }

    /// 让面板出现在鼠标的右下方。
    /// 如果右边或下边空间不够，就自动翻到鼠标的左边或上边，保证面板完整显示在屏幕内。
    ///
    /// 小知识：macOS 的屏幕坐标原点在 **左下角**，y 轴向上，和网页、iOS 正好相反。
    private func originNearMouse(_ mouse: NSPoint, size: NSSize, visible: NSRect) -> NSPoint {
        let gap: CGFloat = 4   // 面板和鼠标之间留一点距离

        var left = mouse.x + gap
        var top = mouse.y - gap
        if left + size.width > visible.maxX {      // 右边放不下 → 放到鼠标左边
            left = mouse.x - gap - size.width
        }
        if top - size.height < visible.minY {      // 下边放不下 → 放到鼠标上边
            top = mouse.y + gap + size.height
        }
        // 最后再确保完全在屏幕可见区域内
        left = min(max(left, visible.minX), visible.maxX - size.width)
        top = min(max(top, visible.minY + size.height), visible.maxY)

        return NSPoint(x: left, y: top - size.height)   // 窗口用左下角作为原点
    }

    private enum Keys {
        static let size = "panelSize"
        static let origin = "panelOrigin"
    }

    // MARK: - 键盘处理

    /// 监听面板里的按键。返回 nil 表示"这个按键我处理掉了"，不再传给搜索框。
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// 用户是不是点过搜索框、正在输入搜索词。
    /// 正在编辑的文本框，键盘焦点其实在系统给它配的"字段编辑器"上
    private var isSearchFocused: Bool {
        (panel?.firstResponder as? NSTextView)?.isFieldEditor == true
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        // 正在用中文输入法打拼音时（有"未确认的文字"），方向键和回车要留给输入法
        if let textView = panel?.firstResponder as? NSTextView, textView.hasMarkedText() {
            return false
        }

        switch Int(event.keyCode) {
        case kVK_UpArrow:
            viewModel.moveSelection(by: -1)
            return true
        case kVK_DownArrow:
            viewModel.moveSelection(by: 1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            viewModel.confirmSelection()
            return true
        case kVK_Escape:
            // 预览开着时先关预览，再按一次才关面板
            preview.isVisible ? preview.hide() : hide()
            return true
        default:
            break
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // 搜索框是空的时候，按空格打开 / 关闭预览（有搜索词时空格要留给打字用）
        if Int(event.keyCode) == kVK_Space && flags.isEmpty && viewModel.query.isEmpty {
            togglePreview()
            return true
        }

        // 只按住了 ⌘ 的组合键：面板自己的快捷键
        if flags == .command && handleCommandKey(event) {
            return true
        }

        // 其他按键（打字、⌘V 等）：用户点过搜索框的话，照常交给搜索框；
        // 没点过的话，说明用户其实是想在原来的应用里继续操作——关掉面板，把这个按键原样交还给它
        if !isSearchFocused {
            passToPreviousApp(event)
            return true
        }
        return false
    }

    /// 面板自己的 ⌘ 快捷键。处理了返回 true
    private func handleCommandKey(_ event: NSEvent) -> Bool {
        if Int(event.keyCode) == kVK_Delete {          // ⌘⌫ 删除
            viewModel.deleteSelected()
            return true
        }
        let key = event.charactersIgnoringModifiers ?? ""
        if key == "p" {                                 // ⌘P 置顶
            viewModel.togglePinSelected()
            return true
        }
        if key == "y" {                                 // ⌘Y 预览（和访达的"快速查看"一样）
            togglePreview()
            return true
        }
        if let number = Int(key), (1...9).contains(number) {   // ⌘1 ~ ⌘9 快速粘贴
            viewModel.quickSelect(index: number - 1)
            return true
        }
        return false
    }

    /// 关掉面板，把按键原样发给原来在用的应用。
    ///
    /// 面板不会抢走那个应用的"前台"状态（见类的说明），所以 frontmostApplication 就是它。
    /// 按键直接投递给它的进程（postToPid），不用等窗口焦点切换回去，后面紧接着打的字顺序也不会乱。
    /// 和自动粘贴一样需要辅助功能权限：没有权限时这一个按键会丢掉，但面板照样会关闭。
    private func passToPreviousApp(_ event: NSEvent) {
        let target = NSWorkspace.shared.frontmostApplication
        hide()
        guard !AppModel.isDemoMode,                       // 演示模式不往别的应用发按键
              let target, target != NSRunningApplication.current,
              let keyEvent = event.cgEvent?.copy() else { return }
        keyEvent.postToPid(target.processIdentifier)
    }
}
