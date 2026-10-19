import Foundation
import Observation

/// 历史面板出现在哪里
enum PanelPlacement: String, CaseIterable, Identifiable {
    case nearMouse      // 鼠标的右下方
    case lastPosition   // 上次拖动到的位置

    var id: String { rawValue }

    var display: String {
        switch self {
        case .nearMouse:    return "鼠标旁边"
        case .lastPosition: return "上次的位置"
        }
    }
}

/// 应用设置。每个属性一被修改，就会通过 didSet 自动保存到 UserDefaults
///（macOS 自带的一个简单的"键值对"存储，适合存设置项）。
/// 加上 @Observable 之后，SwiftUI 界面会在设置变化时自动刷新。
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// 最多保存多少条历史（不含置顶的）
    var maxHistory: Int {
        didSet { defaults.set(maxHistory, forKey: Keys.maxHistory) }
    }

    /// 是否自动清理旧记录
    var autoCleanup: Bool {
        didSet { defaults.set(autoCleanup, forKey: Keys.autoCleanup) }
    }

    /// 自动清理多少天以前的记录（按最后一次复制或使用的时间算）
    var autoCleanupDays: Int {
        didSet { defaults.set(autoCleanupDays, forKey: Keys.autoCleanupDays) }
    }

    /// 自动清理时，置顶的记录是否也删除
    var autoCleanupIncludesPinned: Bool {
        didSet { defaults.set(autoCleanupIncludesPinned, forKey: Keys.autoCleanupIncludesPinned) }
    }

    /// 选中历史后是否自动粘贴到当前应用
    var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Keys.autoPaste) }
    }

    /// 暂停记录（比如要复制一些敏感内容时）
    var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Keys.isPaused) }
    }

    /// 呼出历史面板的快捷键。
    /// 注意：这里只负责保存，真正注册快捷键由 AppModel.changeHotkey 完成。
    var hotkey: Hotkey {
        didSet {
            defaults.set(["keyCode": Int(hotkey.keyCode), "modifiers": Int(hotkey.modifiers)], forKey: Keys.hotkey)
        }
    }

    /// 历史面板出现的位置
    var panelPlacement: PanelPlacement {
        didSet { defaults.set(panelPlacement.rawValue, forKey: Keys.panelPlacement) }
    }

    /// 是否每天自动检查一次更新
    var autoCheckForUpdates: Bool {
        didSet { defaults.set(autoCheckForUpdates, forKey: Keys.autoCheckForUpdates) }
    }

    /// 不记录这些应用里复制的内容（保存的是应用的 Bundle ID，比如 "com.apple.Safari"）
    var ignoredBundleIDs: [String] {
        didSet { defaults.set(ignoredBundleIDs, forKey: Keys.ignoredBundleIDs) }
    }

    init() {
        // 第一次运行时使用的默认值
        defaults.register(defaults: [
            Keys.maxHistory: 200,
            Keys.autoCleanup: false,
            Keys.autoCleanupDays: 30,
            Keys.autoCleanupIncludesPinned: false,
            Keys.autoPaste: true,
            Keys.isPaused: false,
            Keys.panelPlacement: PanelPlacement.nearMouse.rawValue,
            Keys.autoCheckForUpdates: true,
            // 默认忽略"钥匙串访问"和"密码"应用
            Keys.ignoredBundleIDs: ["com.apple.keychainaccess", "com.apple.Passwords"],
        ])
        maxHistory = defaults.integer(forKey: Keys.maxHistory)
        autoCleanup = defaults.bool(forKey: Keys.autoCleanup)
        autoCleanupDays = defaults.integer(forKey: Keys.autoCleanupDays)
        autoCleanupIncludesPinned = defaults.bool(forKey: Keys.autoCleanupIncludesPinned)
        autoPaste = defaults.bool(forKey: Keys.autoPaste)
        isPaused = defaults.bool(forKey: Keys.isPaused)
        hotkey = Self.loadHotkey(from: defaults)
        panelPlacement = PanelPlacement(rawValue: defaults.string(forKey: Keys.panelPlacement) ?? "") ?? .nearMouse
        autoCheckForUpdates = defaults.bool(forKey: Keys.autoCheckForUpdates)
        ignoredBundleIDs = defaults.stringArray(forKey: Keys.ignoredBundleIDs) ?? []
    }

    /// 读取保存的快捷键。旧版本保存的是预设的名字（字符串），新版本保存的是按键码 + 修饰键（字典）
    private static func loadHotkey(from defaults: UserDefaults) -> Hotkey {
        if let saved = defaults.dictionary(forKey: Keys.hotkey),
           let keyCode = saved["keyCode"] as? Int,
           let modifiers = saved["modifiers"] as? Int {
            return Hotkey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        }
        if let legacyName = defaults.string(forKey: Keys.hotkey) {
            return Hotkey(legacyName: legacyName) ?? .default
        }
        return .default
    }

    private enum Keys {
        static let maxHistory = "maxHistory"
        static let autoCleanup = "autoCleanup"
        static let autoCleanupDays = "autoCleanupDays"
        static let autoCleanupIncludesPinned = "autoCleanupIncludesPinned"
        static let autoPaste = "autoPaste"
        static let isPaused = "isPaused"
        static let hotkey = "hotkey"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let panelPlacement = "panelPlacement"
        static let autoCheckForUpdates = "autoCheckForUpdates"
    }
}
