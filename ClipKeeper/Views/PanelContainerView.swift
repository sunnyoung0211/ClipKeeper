import AppKit
import QuartzCore
import SwiftUI

/// 浮动面板窗口最外层的视图，负责：
/// 1. 一块圆角玻璃背景：macOS 26 及以上用液态玻璃，旧系统退回毛玻璃；
/// 2. 玻璃下面一层柔和的圆角阴影；
/// 3. 让用户拖动四条边、四个角来调整大小（带最小 / 最大尺寸限制）。
///
/// 窗口比玻璃大一圈，多出来的透明边距是留给阴影的：
///
///     ┌────────── 窗口（透明）──────────┐
///     │   ╭────── 圆角玻璃 ──────╮      │
///     │   │                     │      │
///     │   ╰─────────────────────╯      │
///     │        ░░░ 阴影 ░░░            │
///     └────────────────────────────────┘
///
/// 为什么不用系统自带的窗口阴影？
/// 系统阴影是按"整个窗口"计算的。玻璃效果由系统特殊渲染，系统无法从中识别出圆角形状，
/// 于是会在四个角外面画出一圈直角的阴影和边线。所以这里关掉系统阴影，自己按圆角形状画。
final class PanelContainerView: NSView {
    /// 玻璃四周留给阴影的透明边距（阴影向下偏，所以下边留得多一些）
    static let shadowMargins = NSEdgeInsets(top: 24, left: 32, bottom: 44, right: 32)

    /// 这个外壳实际使用的边距。默认就是 shadowMargins；预览窗口贴着历史面板的那一侧会留得窄一些
    var margins = PanelContainerView.shadowMargins {
        didSet { setFrameSize(frame.size) }
    }
    /// 能不能拖动边缘调整大小（预览窗口不能）
    var isResizable = true
    var minSize = NSSize(width: 300, height: 260)
    var maxSize = NSSize(width: 640, height: 820)
    /// 拖动调整大小结束时调用（用来保存新尺寸）
    var onResizeEnded: (() -> Void)?
    /// 点击了玻璃外面的透明区域（应该当作"点了面板外面"，关闭面板）
    var onClickOutside: (() -> Void)?

    private let cornerRadius: CGFloat
    /// 边缘多宽的范围内可以拖动缩放（玻璃边缘内外各算这么宽）
    private let edgeThickness: CGFloat = 5
    /// 角落的可拖动范围更大一些，方便同时调整宽和高
    private let cornerSize: CGFloat = 18

    private let shadowView = PanelShadowView()
    private let glassView: NSView

    // 拖动过程中记录的状态
    private var resizingEdges: Edges = []
    private var dragStartMouse = NSPoint.zero
    private var dragStartFrame = NSRect.zero
    private var isShowingResizeCursor = false

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        glassView = Self.makeGlassView(cornerRadius: cornerRadius)
        super.init(frame: .zero)

        addSubview(shadowView)   // 先加阴影，它在最下面
        addSubview(glassView)    // 玻璃盖在阴影上面

        // 跟踪鼠标移动，用来在边缘处切换成"调整大小"的鼠标指针
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 玻璃在这个视图里的位置 = 整个区域去掉四周的阴影边距
    var glassFrame: NSRect {
        let m = margins
        return NSRect(
            x: m.left, y: m.bottom,
            width: max(bounds.width - m.left - m.right, 0),
            height: max(bounds.height - m.top - m.bottom, 0)
        )
    }

    /// 设置玻璃上面显示的内容（我们的 SwiftUI 界面）
    func setContent(_ content: NSView) {
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
            glass.contentView = content
        } else {
            glassView.subviews.forEach { $0.removeFromSuperview() }
            content.frame = glassView.bounds
            glassView.addSubview(content)
        }
    }

    /// 视图大小变化时（打开面板、拖动缩放），重新摆放玻璃和阴影
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        shadowView.frame = bounds
        glassView.frame = glassFrame
        shadowView.update(glassFrame: glassFrame, cornerRadius: cornerRadius)
    }

    // MARK: - 玻璃背景

    private static func makeGlassView(cornerRadius: CGFloat) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            return glass
        }
        // 旧系统：毛玻璃 + 圆角遮罩
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(radius: cornerRadius)
        return effect
    }

    /// 生成一张可拉伸的圆角矩形图片，作为毛玻璃的形状遮罩
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let length = radius * 2 + 1
        let image = NSImage(size: NSSize(width: length, height: length), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        // 四个角保持不变，中间部分拉伸
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: - 判断鼠标在哪条边上

    /// 玻璃的边（可以组合，比如 [.top, .left] 表示左上角）
    private struct Edges: OptionSet {
        let rawValue: Int
        static let left   = Edges(rawValue: 1 << 0)
        static let right  = Edges(rawValue: 1 << 1)
        static let top    = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    /// 计算某个点落在玻璃的哪些边上。注意：AppKit 视图坐标的原点在左下角，y 向上。
    private func edges(at point: NSPoint) -> Edges {
        guard isResizable else { return [] }
        let g = glassFrame
        let t = edgeThickness, c = cornerSize
        // 先排除离玻璃太远的点
        guard g.insetBy(dx: -t, dy: -t).contains(point) else { return [] }

        let nearLeft = abs(point.x - g.minX) <= t
        let nearRight = abs(point.x - g.maxX) <= t
        let nearBottom = abs(point.y - g.minY) <= t
        let nearTop = abs(point.y - g.maxY) <= t

        var edges: Edges = []
        if nearLeft || ((nearTop || nearBottom) && point.x <= g.minX + c) { edges.insert(.left) }
        if nearRight || ((nearTop || nearBottom) && point.x >= g.maxX - c) { edges.insert(.right) }
        if nearBottom || ((nearLeft || nearRight) && point.y <= g.minY + c) { edges.insert(.bottom) }
        if nearTop || ((nearLeft || nearRight) && point.y >= g.maxY - c) { edges.insert(.top) }
        return edges
    }

    /// 决定鼠标点击交给谁处理：
    /// 边缘 → 我们自己（缩放）；玻璃里面 → SwiftUI 界面；玻璃外面的透明区域 → 我们自己（关闭面板）
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if !edges(at: local).isEmpty || !glassFrame.contains(local) {
            return self
        }
        return super.hitTest(point)
    }

    // MARK: - 拖动缩放

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        resizingEdges = edges(at: point)
        if resizingEdges.isEmpty {
            // 点在了玻璃外面的透明区域，看起来就是点在了面板外面
            onClickOutside?()
            return
        }
        dragStartMouse = NSEvent.mouseLocation
        dragStartFrame = window?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard !resizingEdges.isEmpty, let window else { return }

        // 用屏幕坐标计算鼠标移动了多少（窗口自己在变，不能用窗口内的坐标）
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragStartMouse.x
        let dy = mouse.y - dragStartMouse.y

        // 尺寸限制针对的是玻璃，窗口还要再加上四周的阴影边距
        let m = margins
        let extraWidth = m.left + m.right
        let extraHeight = m.top + m.bottom
        let minWidth = minSize.width + extraWidth, maxWidth = maxSize.width + extraWidth
        let minHeight = minSize.height + extraHeight, maxHeight = maxSize.height + extraHeight

        var frame = dragStartFrame
        if resizingEdges.contains(.right) {
            frame.size.width = clamp(dragStartFrame.width + dx, minWidth, maxWidth)
        }
        if resizingEdges.contains(.left) {
            // 拖左边：右边保持不动，宽度和左边位置一起变
            frame.size.width = clamp(dragStartFrame.width - dx, minWidth, maxWidth)
            frame.origin.x = dragStartFrame.maxX - frame.width
        }
        if resizingEdges.contains(.top) {
            frame.size.height = clamp(dragStartFrame.height + dy, minHeight, maxHeight)
        }
        if resizingEdges.contains(.bottom) {
            // 拖下边：上边保持不动
            frame.size.height = clamp(dragStartFrame.height - dy, minHeight, maxHeight)
            frame.origin.y = dragStartFrame.maxY - frame.height
        }
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        if !resizingEdges.isEmpty {
            onResizeEnded?()
        }
        resizingEdges = []
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    // MARK: - 鼠标指针

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: edges(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        updateCursor(for: [])
    }

    private func updateCursor(for edges: Edges) {
        if let cursor = Self.resizeCursor(for: edges) {
            cursor.set()
            isShowingResizeCursor = true
        } else if isShowingResizeCursor {
            // 离开边缘时恢复普通箭头（只恢复一次，避免覆盖搜索框里的文字光标）
            NSCursor.arrow.set()
            isShowingResizeCursor = false
        }
    }

    private static func resizeCursor(for edges: Edges) -> NSCursor? {
        guard !edges.isEmpty else { return nil }
        if #available(macOS 15.0, *) {
            // macOS 15 开始提供和系统窗口完全一致的缩放指针
            let position: NSCursor.FrameResizePosition
            switch edges {
            case [.top, .left]:     position = .topLeft
            case [.top, .right]:    position = .topRight
            case [.bottom, .left]:  position = .bottomLeft
            case [.bottom, .right]: position = .bottomRight
            case .left:             position = .left
            case .right:            position = .right
            case .top:              position = .top
            default:                position = .bottom
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        // macOS 14 只有水平 / 垂直两种缩放指针
        if edges == .left || edges == .right { return .resizeLeftRight }
        if edges == .top || edges == .bottom { return .resizeUpDown }
        return .crosshair
    }
}

/// 玻璃下面的圆角阴影。
///
/// 模仿 macOS 窗口阴影的做法，叠了两层：
/// - 一层大而淡的"环境阴影"，让面板看起来浮在桌面上；
/// - 一层小而清晰的"接触阴影"，勾勒出边缘。
///
/// 玻璃是半透明的，如果阴影也画在玻璃正下方，会透过玻璃把里面弄脏，
/// 所以给阴影加了一个"中间挖空"的遮罩：只在玻璃外面显示阴影。
private final class PanelShadowView: NSView {
    private let ambientLayer = CALayer()
    private let contactLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // 先设置 layer 再打开 wantsLayer：这样这个视图的图层完全由我们自己管理
        layer = CALayer()
        wantsLayer = true

        configure(ambientLayer, opacity: 0.22, radius: 18, offsetY: -8)
        configure(contactLayer, opacity: 0.14, radius: 1.5, offsetY: -0.5)
        layer?.addSublayer(ambientLayer)
        layer?.addSublayer(contactLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 阴影不参与鼠标点击
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func configure(_ shadowLayer: CALayer, opacity: Float, radius: CGFloat, offsetY: CGFloat) {
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = opacity
        shadowLayer.shadowRadius = radius
        // macOS 上图层坐标的 y 轴向上，所以负数表示阴影往下偏
        shadowLayer.shadowOffset = CGSize(width: 0, height: offsetY)
    }

    /// 根据玻璃的位置和圆角，更新阴影的形状
    func update(glassFrame: NSRect, cornerRadius: CGFloat) {
        // 改图层属性时默认会带动画，这里关掉，避免缩放窗口时阴影"慢半拍"
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let shape = CGPath(roundedRect: glassFrame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        for shadowLayer in [ambientLayer, contactLayer] {
            shadowLayer.frame = bounds
            shadowLayer.shadowPath = shape
            shadowLayer.mask = makeCutoutMask(cutout: shape)
        }

        CATransaction.commit()
    }

    /// 遮罩：整个区域都显示，只有玻璃那块圆角矩形"挖空"不显示
    private func makeCutoutMask(cutout: CGPath) -> CAShapeLayer {
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addPath(cutout)
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = path
        mask.fillRule = .evenOdd   // 奇偶填充：两个形状重叠的部分不填充，正好挖出一个洞
        return mask
    }
}

/// 一块"可以按住拖动窗口"的区域，放在 SwiftUI 界面的空白处使用：
/// `.background(WindowDragArea())`
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            // 交给系统处理窗口拖动，跟拖动普通窗口标题栏的手感一样
            window?.performDrag(with: event)
        }
    }
}
