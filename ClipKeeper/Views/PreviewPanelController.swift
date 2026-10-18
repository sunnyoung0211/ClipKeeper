import AppKit
import QuartzCore
import SwiftUI

/// 预览窗口：在历史面板里按空格（或 ⌘Y）时，在面板旁边显示选中记录的完整内容。
///
/// 和历史面板一样是一个无边框、圆角玻璃的浮动窗口，但它 **不能成为焦点窗口**：
/// 键盘焦点始终留在历史面板上，上下键切换选中项时，预览会跟着更新。
final class PreviewPanelController {
    private let store: ClipboardStore
    private var panel: PreviewPanel?
    private var container: PanelContainerView?
    /// 显示内容的 SwiftUI 视图。整个窗口只用这一个，切换记录时只换里面的内容
    private var hostingView: NSHostingView<AnyView>?
    /// 正在预览的记录
    private var item: ClipItem?

    /// 预览窗口和历史面板之间的距离
    private static let gap: CGFloat = 10

    init(store: ClipboardStore) {
        self.store = store
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    /// 窗口在屏幕上的位置（演示模式截图时用）
    var frame: NSRect? {
        isVisible ? panel?.frame : nil
    }

    /// 显示某条记录的预览，放在 anchor（历史面板玻璃部分在屏幕上的位置）旁边
    func show(_ item: ClipItem, nextTo anchor: NSRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // 换内容、改窗口大小时关掉所有动画。
        // 否则旧内容会用一个很快的淡出动画消失，而窗口已经变成了新的大小和位置，
        // 看起来就像旧图片突然移了位、闪一下才消失。
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if item.id != self.item?.id {
                // .id(...)：换成另一条记录时，SwiftUI 会把界面当成全新的（比如大图状态会清空重新加载）
                hostingView?.rootView = AnyView(ClipPreviewView(item: item, store: store).id(item.id))
                self.item = item
            }
            place(nextTo: anchor)
            CATransaction.commit()
        }

        if !panel.isVisible {
            // 淡入，显得不那么突兀
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    /// 历史面板移动或改变大小后，跟着调整位置
    func reposition(nextTo anchor: NSRect) {
        guard isVisible else { return }
        place(nextTo: anchor)
    }

    func hide() {
        panel?.orderOut(nil)
        item = nil
    }

    // MARK: - 创建窗口

    private func makePanel() -> PreviewPanel {
        let panel = PreviewPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false               // 阴影由 PanelContainerView 按圆角形状自己画
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let container = PanelContainerView(cornerRadius: PanelController.cornerRadius)
        container.isResizable = false
        panel.contentView = container
        self.container = container

        let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        hostingView.sizingOptions = []   // 窗口大小由我们决定
        container.setContent(hostingView)
        self.hostingView = hostingView
        return panel
    }

    // MARK: - 位置和大小

    /// 优先放在历史面板右边，右边放不下就放左边；顶部和历史面板对齐
    private func place(nextTo anchor: NSRect) {
        guard let panel, let container, let item else { return }
        let size = PreviewLayout.glassSize(for: item)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchor

        let onRight = anchor.maxX + Self.gap + size.width <= visible.maxX
        var x = onRight ? anchor.maxX + Self.gap : anchor.minX - Self.gap - size.width
        x = min(max(x, visible.minX), visible.maxX - size.width)
        let top = min(max(anchor.maxY, visible.minY + size.height), visible.maxY)
        let glass = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)

        // 贴着历史面板的那一侧只留出两个窗口之间的空隙作为边距：
        // 默认的阴影边距比空隙宽，透明的边距会盖住历史面板的边缘，挡住鼠标点击
        var margins = PanelContainerView.shadowMargins
        if onRight {
            margins.left = Self.gap
        } else {
            margins.right = Self.gap
        }
        container.margins = margins
        panel.setFrame(NSRect(
            x: glass.minX - margins.left,
            y: glass.minY - margins.bottom,
            width: glass.width + margins.left + margins.right,
            height: glass.height + margins.top + margins.bottom
        ), display: true)
    }
}

/// 不能成为焦点窗口的面板：点它、在它上面滚动，键盘焦点都还留在历史面板上
private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
