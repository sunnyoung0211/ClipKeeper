import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 快捷键录制框（设置窗口里使用）。
///
/// 点一下进入"录制"状态，然后直接按下想要的组合键（比如 ⌃⌥V）就会保存；
/// 录制时按 esc、再点一下录制框，或者切换到别的窗口，都会取消录制。
struct HotkeyRecorderView: View {
    let app: AppModel

    @State private var recorder = KeyRecorder()
    /// 按下的组合键不能用时，在下面显示原因
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if app.settings.hotkey != .default && !recorder.isRecording {
                    Button {
                        apply(.default)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("恢复默认（\(Hotkey.default.display)）")
                }
                Button(action: toggleRecording) {
                    field
                }
                .buttonStyle(.plain)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { recorder.stop() }
    }

    /// 录制框本体：平时显示当前的快捷键，录制时显示提示和已经按住的修饰键
    private var field: some View {
        Text(fieldText)
            .font(.system(size: 13, weight: recorder.isRecording ? .regular : .medium))
            .foregroundStyle(recorder.isRecording ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .frame(minWidth: 96)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(.primary.opacity(recorder.isRecording ? 0.02 : 0.06),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                // 录制时用强调色描边，提示"正在等你按键"
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(recorder.isRecording ? Color.accentColor : Color.primary.opacity(0.12),
                                  lineWidth: recorder.isRecording ? 1.5 : 0.5)
            }
            .contentShape(Rectangle())
            .help(recorder.isRecording ? "按下新的快捷键，按 esc 取消" : "点击后按下新的快捷键")
    }

    private var fieldText: String {
        guard recorder.isRecording else { return app.settings.hotkey.display }
        let held = Hotkey.symbols(for: recorder.heldModifiers)
        return held.isEmpty ? "请按下快捷键…" : held + "…"
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
            return
        }
        message = nil
        app.pauseHotkey()
        recorder.start(
            onKey: { hotkey in apply(hotkey) },      // 返回 true 表示接受，结束录制
            onEnd: { app.resumeHotkey() }
        )
    }

    /// 尝试换成新的快捷键，返回是否成功
    @discardableResult
    private func apply(_ hotkey: Hotkey) -> Bool {
        message = app.changeHotkey(to: hotkey)
        return message == nil
    }
}

/// 在录制期间"截获"键盘事件。
@Observable
final class KeyRecorder {
    private(set) var isRecording = false
    /// 当前按住的修饰键（录制时实时显示，比如按住 ⌃⌥ 时显示 "⌃⌥…"）
    private(set) var heldModifiers: UInt32 = 0

    @ObservationIgnored private var onKey: ((Hotkey) -> Bool)?
    @ObservationIgnored private var onEnd: (() -> Void)?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?

    /// 开始录制。
    /// - Parameters:
    ///   - onKey: 按下了一个组合键。返回 true 表示接受并结束录制，返回 false 表示继续等待
    ///   - onEnd: 录制结束（无论是录好了还是取消了）
    func start(onKey: @escaping (Hotkey) -> Bool, onEnd: @escaping () -> Void) {
        guard !isRecording else { return }
        isRecording = true
        heldModifiers = 0
        self.onKey = onKey
        self.onEnd = onEnd

        // "本地监听"能在按键被分发给窗口和菜单之前拿到它（所以 ⌘Q 这类组合也能录到），
        // 返回 nil 表示把这个按键"吞掉"，不再继续传递
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        // 窗口失去焦点（切到别的应用、关掉设置窗口）时取消录制
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        heldModifiers = 0
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        keyMonitor = nil
        resignObserver = nil

        let onEnd = self.onEnd
        self.onKey = nil
        self.onEnd = nil
        onEnd?()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // 只按下或松开了修饰键：更新显示，让用户看到自己按住了哪些键
        if event.type == .flagsChanged {
            heldModifiers = Hotkey.carbonModifiers(from: event.modifierFlags)
            return event
        }
        let hotkey = Hotkey(event: event)
        if hotkey.keyCode == UInt32(kVK_Escape) && hotkey.modifiers == 0 {
            stop()                         // 单独按 esc：取消录制
        } else if onKey?(hotkey) == true {
            stop()
        }
        return nil
    }
}
