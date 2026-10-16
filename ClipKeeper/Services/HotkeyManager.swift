import Carbon.HIToolbox

/// 注册"全局快捷键"——无论当前在哪个应用里，按下都能触发。
///
/// 这里用的是苹果很老的 Carbon API。它看起来有点古怪（要和 C 语言风格的函数打交道），
/// 但至今仍是注册全局快捷键最简单、且不需要额外权限的方式。
final class HotkeyManager {
    /// 快捷键被按下时要执行的操作
    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// 注册快捷键（会先取消之前注册的）。返回是否注册成功。
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        installHandlerIfNeeded()

        // 快捷键的身份标识：signature 是任意 4 个字符组成的编号，这里用 "CLKP"
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_4B50), id: 1)
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    /// 安装事件处理函数：系统在快捷键被按下时会调用它
    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // C 函数不能直接捕获 Swift 对象，所以把 self 转成一个指针传进去，回调时再转回来
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated {
                manager.onPressed?()
            }
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)
    }
}
