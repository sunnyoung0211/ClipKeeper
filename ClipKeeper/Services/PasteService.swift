import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 负责把历史记录写回剪贴板，以及"自动粘贴"。
///
/// 自动粘贴的原理：先把内容放进剪贴板，再模拟用户按下 ⌘V。
/// 模拟按键属于"控制电脑"的能力，macOS 要求用户在
/// 「系统设置 → 隐私与安全性 → 辅助功能」里手动允许，否则按键会被系统忽略。
final class PasteService {
    private let settings: AppSettings

    /// 本次运行中是否已经弹过系统的授权提示 / 我们自己的说明窗口（避免反复打扰用户）
    private var hasRequestedPermission = false
    private var hasShownPermissionHelp = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - 写入剪贴板

    /// 把一条记录写入系统剪贴板，返回是否成功。
    ///
    /// 注意顺序：先准备好要写入的内容，确认没问题后才清空剪贴板。
    /// 否则一旦内容有问题，用户的剪贴板就被清空了，按 ⌘V 会什么都粘贴不出来。
    func writeToPasteboard(_ item: ClipItem) -> Bool {
        // 这条记录可能刚刚被删除了（比如超出数量被自动清理）
        guard !item.isDeleted else { return false }

        let pasteboardItems: [NSPasteboardItem]
        switch item.kind {
        case .text:
            guard let text = item.text, !text.isEmpty else { return false }
            let pbItem = NSPasteboardItem()
            pbItem.setString(text, forType: .string)
            pasteboardItems = [pbItem]

        case .image:
            guard let png = item.imageData else { return false }
            // 同时提供 PNG 和 TIFF 两种格式，兼容更多应用
            let pbItem = NSPasteboardItem()
            pbItem.setData(png, forType: .png)
            if let tiff = NSImage(data: png)?.tiffRepresentation {
                pbItem.setData(tiff, forType: .tiff)
            }
            pasteboardItems = [pbItem]

        case .file:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) }
            guard !urls.isEmpty else { return false }
            pasteboardItems = urls.map { url in
                let pbItem = NSPasteboardItem()
                pbItem.setString(url.absoluteString, forType: .fileURL)
                // 同时附带文件名文本：粘贴到文本框时会得到文件名（和 Finder 的行为一致），而不是什么都没有
                pbItem.setString(url.lastPathComponent, forType: .string)
                return pbItem
            }
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects(pasteboardItems)
    }

    // MARK: - 自动粘贴

    /// 如果开启了自动粘贴，就模拟按下 ⌘V
    func pasteIfEnabled() {
        guard settings.autoPaste else { return }
        guard Self.isAccessibilityTrusted else {
            handleMissingPermission()
            return
        }
        // 如果设置窗口正在前台，先让出前台，这样 ⌘V 才会发给用户原来在用的应用
        if NSApp.isActive {
            NSApp.deactivate()
        }
        // 稍等一下，确保面板已经关闭、焦点回到了原来的应用
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.sendCommandV()
        }
    }

    /// 没有权限时的处理：
    /// 第一次 → 弹出系统自带的授权提示（同时会把 ClipKeeper 加进"辅助功能"列表）；
    /// 第二次 → 弹出我们自己的说明，解释"开关明明打开了却还提示"的原因；
    /// 之后   → 不再打扰（内容已经在剪贴板里，用户可以手动 ⌘V）。
    private func handleMissingPermission() {
        if !hasRequestedPermission {
            hasRequestedPermission = true
            Self.requestAccessibility()
        } else if !hasShownPermissionHelp {
            hasShownPermissionHelp = true
            showPermissionHelp()
        }
    }

    private func showPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "自动粘贴需要「辅助功能」权限"
        alert.informativeText = """
        内容已经复制到剪贴板，你可以先手动按 ⌘V 粘贴。

        如果系统设置里 ClipKeeper 的开关已经打开，却仍然出现这个提示：\
        这通常是因为应用重新编译后签名变了，系统把它当成了"另一个应用"。\
        请在辅助功能列表中选中 ClipKeeper，点「−」删除，然后重新打开 ClipKeeper 再授权一次。
        """
        alert.addButton(withTitle: "打开辅助功能设置")
        alert.addButton(withTitle: "关闭自动粘贴")
        alert.addButton(withTitle: "取消")

        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Self.openAccessibilitySettings()
        case .alertSecondButtonReturn:
            settings.autoPaste = false
        default:
            break
        }
    }

    // MARK: - 辅助功能权限

    /// 是否已获得辅助功能权限（每次都实时向系统查询）
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统对话框，引导用户去授权
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 直接打开系统设置里的"辅助功能"页面
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            OpenHelper.openSystemSettings(url)
        }
    }

    // MARK: - 模拟按键

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
