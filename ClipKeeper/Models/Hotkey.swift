import AppKit
import Carbon.HIToolbox

/// 呼出面板的快捷键：一个按键 + 若干修饰键（⌃ ⌥ ⇧ ⌘）。
///
/// 保存的是 Carbon API 使用的"按键码"和"修饰键"，注册全局快捷键时可以直接用。
/// 按键码对应的是键盘上的 **物理位置**（比如 kVK_ANSI_V 是 V 键所在的位置），
/// 和当前用的是什么输入法无关，所以切换到中文输入法时快捷键照样能用。
struct Hotkey: Equatable {
    var keyCode: UInt32
    /// Carbon 的修饰键组合：cmdKey、optionKey、controlKey、shiftKey 按位相加
    var modifiers: UInt32

    /// 默认快捷键 ⇧⌘V
    static let `default` = Hotkey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 0.1.1 及以前的版本只能从 4 个预设里选，设置里保存的是预设的名字，这里把它换算成新的格式
    init?(legacyName: String) {
        let v = UInt32(kVK_ANSI_V)
        switch legacyName {
        case "cmdShiftV":  self.init(keyCode: v, modifiers: UInt32(cmdKey | shiftKey))
        case "optionCmdV": self.init(keyCode: v, modifiers: UInt32(cmdKey | optionKey))
        case "ctrlCmdV":   self.init(keyCode: v, modifiers: UInt32(cmdKey | controlKey))
        case "ctrlShiftV": self.init(keyCode: v, modifiers: UInt32(controlKey | shiftKey))
        default:           return nil
        }
    }

    // MARK: - 显示

    /// 显示给用户看的文字，比如 "⇧⌘V"
    var display: String {
        Self.symbols(for: modifiers) + keyName
    }

    /// 把修饰键转成符号。顺序按 macOS 的惯例：⌃ ⌥ ⇧ ⌘
    static func symbols(for modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    /// 按键本身的名字：特殊按键用符号，字母、数字等按当前键盘布局显示
    private var keyName: String {
        if let name = Self.specialKeyNames[Int(keyCode)] { return name }
        return Self.character(for: keyCode) ?? "键码\(keyCode)"
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Space: "空格",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// 查出某个按键在当前键盘布局下对应的字符（比如 kVK_ANSI_V → "V"）。
    /// 用"ASCII 键盘布局"来查，这样用中文输入法时也能得到英文字母。
    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { buffer in
            UCKeyTranslate(
                buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress,
                UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text.uppercased()
    }

    // MARK: - 从键盘事件创建

    /// 把 AppKit 的修饰键转换成 Carbon 的格式
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    init(event: NSEvent) {
        self.init(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(from: event.modifierFlags))
    }

    // MARK: - 检查能不能用

    /// 检查这个组合适不适合当全局快捷键。可以用时返回 nil，不能用时返回原因。
    var problem: String? {
        let hasCommand = modifiers & UInt32(cmdKey) != 0
        let hasOption = modifiers & UInt32(optionKey) != 0
        let hasControl = modifiers & UInt32(controlKey) != 0
        let hasShift = modifiers & UInt32(shiftKey) != 0
        // F1 ~ F20 平时很少用来打字，单独按也可以作为快捷键
        let isFunctionKey = Self.specialKeyNames[Int(keyCode)]?.hasPrefix("F") == true

        if !isFunctionKey {
            if !hasCommand && !hasOption && !hasControl {
                return "请至少包含 ⌘、⌥ 或 ⌃ 中的一个"
            }
            if hasOption && !hasCommand && !hasControl {
                return "只用 ⌥ 或 ⌥⇧ 的组合是用来输入特殊字符的，请再加上 ⌘ 或 ⌃"
            }
            if hasCommand && !hasOption && !hasControl && !hasShift {
                return "只用 ⌘ 的组合会和应用里的常用快捷键冲突（比如 ⌘C、⌘V），请再加上 ⇧、⌥ 或 ⌃"
            }
        }
        if isUsedBySystem {
            return "\(display) 已经是系统快捷键，可以在「系统设置 → 键盘 → 键盘快捷键」中查看"
        }
        return nil
    }

    /// 是否和系统已启用的快捷键（比如 ⌘空格 打开聚焦搜索、⇧⌘3 截屏）重复
    private var isUsedBySystem: Bool {
        var unmanagedList: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanagedList) == noErr,
              let list = unmanagedList?.takeRetainedValue() as? [[String: Any]] else { return false }
        let mask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        return list.contains { entry in
            guard (entry[kHISymbolicHotKeyEnabled] as? Bool) == true,
                  let code = entry[kHISymbolicHotKeyCode] as? Int,
                  let systemModifiers = entry[kHISymbolicHotKeyModifiers] as? Int else { return false }
            return UInt32(code) == keyCode && UInt32(systemModifiers) & mask == modifiers
        }
    }
}
