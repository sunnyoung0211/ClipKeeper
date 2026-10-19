import AppKit
import SwiftUI

/// 整个应用的"总管"：创建并持有各个模块，并把它们连接起来。
///
/// 各模块的分工：
/// - AppSettings       设置项
/// - ClipboardStore    历史数据（SwiftData 数据库）
/// - ClipboardMonitor  监听系统剪贴板
/// - PasteService      写回剪贴板 / 自动粘贴
/// - HotkeyManager     全局快捷键
/// - PanelController   浮动的历史面板
/// - UpdateService     检查更新、下载并安装新版本
final class AppModel {
    /// 全局唯一的实例（单例），界面里通过 AppModel.shared 访问
    static let shared = AppModel()

    let settings: AppSettings
    let store: ClipboardStore
    let monitor: ClipboardMonitor
    let pasteService: PasteService
    let panelController: PanelController
    let updater = UpdateService()
    private let hotkeyManager = HotkeyManager()
    /// 是否正在录制新快捷键（录制期间暂停当前的快捷键）
    private var isHotkeyPaused = false
    private var settingsWindow: NSWindow?
    /// 每小时检查一次要不要自动清理旧记录
    private var cleanupTimer: Timer?

    private init() {
        settings = AppSettings()
        store = ClipboardStore(settings: settings, inMemory: Self.isDemoMode)
        monitor = ClipboardMonitor(store: store, settings: settings)
        pasteService = PasteService(settings: settings)
        panelController = PanelController(store: store, settings: settings)

        // 把各模块"连线"
        panelController.onSelect = { [weak self] item in self?.paste(item) }
        panelController.onCopyOnly = { [weak self] item in _ = self?.copy(item) }
        hotkeyManager.onPressed = { [weak self] in self?.panelController.toggle() }
    }

    /// 应用启动完成后调用
    func start() {
        #if DEBUG
        if Self.isDemoMode {
            // 演示模式：不监听剪贴板、不注册快捷键，只放入示例数据，专门用来截图
            DemoData.fill(store)
            DemoData.openRequestedWindows(app: self)
            return
        }
        #endif

        monitor.start()
        registerHotkey()
        startAutoCleanup()
        updater.startAutomaticChecks { [weak self] in
            self?.settings.autoCheckForUpdates ?? false
        }

        #if DEBUG
        // 调试用：用启动参数 `-ShowPanelOnLaunch YES` 运行时，启动后直接打开面板，方便查看界面
        if UserDefaults.standard.bool(forKey: "ShowPanelOnLaunch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPanel() }
        }
        #endif
    }

    /// 是否处于演示模式（只在 Debug 版本中可用，用启动参数 `-DemoMode YES` 打开）
    static var isDemoMode: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "DemoMode")
        #else
        false
        #endif
    }

    // MARK: - 常用操作

    /// 粘贴某条记录：关闭面板 → 写入剪贴板 → （可选）自动按 ⌘V
    func paste(_ item: ClipItem) {
        panelController.hide()
        guard copy(item) else { return }
        pasteService.pasteIfEnabled()
    }

    /// 只复制到剪贴板，不自动粘贴。返回是否成功。
    @discardableResult
    func copy(_ item: ClipItem) -> Bool {
        guard pasteService.writeToPasteboard(item) else {
            NSSound.beep()   // 写入失败时"嘟"一声提示用户，而不是悄悄留下一个空剪贴板
            return false
        }
        monitor.ignoreCurrentChange()   // 这是我们自己写入的，不要再记录一遍
        store.bump(item)                // 用过的记录移到最前面
        return true
    }

    func showPanel() {
        panelController.show()
    }

    /// 打开设置窗口
    /// - Parameter revealUpdates: 打开后滚动到"更新"分组（从菜单里的"发现新版本"进来时）
    func showSettings(revealUpdates: Bool = false) {
        if revealUpdates {
            updater.wantsReveal = true
        }
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(app: self)))
            window.title = "ClipKeeper 设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        // 菜单栏应用默认不在前台，需要主动激活，窗口才会显示在最前面
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 自动清理

    /// 启动时清理一次旧记录，之后每小时检查一次
    private func startAutoCleanup() {
        store.applyAutoCleanup()
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // 面板开着时先不删，免得用户正在看、正在预览的记录突然消失，下个小时再清理
                guard let self, !self.panelController.isVisible else { return }
                self.store.applyAutoCleanup()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cleanupTimer = timer
    }

    // MARK: - 快捷键

    /// 换成新的快捷键。成功返回 nil；不能用时返回原因，并保持原来的快捷键不变。
    func changeHotkey(to newHotkey: Hotkey) -> String? {
        if let problem = newHotkey.problem { return problem }
        if !Self.isDemoMode {
            guard hotkeyManager.register(newHotkey) else {
                if !isHotkeyPaused { registerHotkey() }   // 新的注册失败，换回原来的
                return "\(newHotkey.display) 注册失败，可能已被系统或其他应用占用，请换一个"
            }
        }
        settings.hotkey = newHotkey
        return nil
    }

    /// 录制新快捷键时，先暂时停用当前的快捷键，否则按下它会直接打开面板，录制框收不到
    func pauseHotkey() {
        isHotkeyPaused = true
        hotkeyManager.unregister()
    }

    /// 录制结束后恢复快捷键
    func resumeHotkey() {
        isHotkeyPaused = false
        guard !Self.isDemoMode else { return }   // 演示模式本来就不注册快捷键
        registerHotkey()
    }

    /// 注册快捷键。
    /// 刚启动时旧实例可能还没完全退出、仍占着快捷键，所以失败后会稍等再重试几次。
    private func registerHotkey(retries: Int = 6) {
        if hotkeyManager.register(settings.hotkey) { return }
        guard retries > 0 else {
            print("快捷键 \(settings.hotkey.display) 注册失败，可能已被其他应用占用")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.registerHotkey(retries: retries - 1)
        }
    }
}
