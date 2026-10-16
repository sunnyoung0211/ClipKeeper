import Foundation
import Observation

/// 可选的呼出快捷键。
/// 为了保持简单，这里提供几个预设，而不是让用户自己录制任意按键。
enum HotkeyOption: String, CaseIterable, Identifiable {
    case cmdShiftV
    case optionCmdV
    case ctrlCmdV
    case ctrlShiftV

    var id: String { rawValue }

    /// 显示给用户看的文字
    var display: String {
        switch self {
        case .cmdShiftV:  return "⇧⌘V"
        case .optionCmdV: return "⌥⌘V"
        case .ctrlCmdV:   return "⌃⌘V"
        case .ctrlShiftV: return "⌃⇧V"
        }
    }
}

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

    /// 选中历史后是否自动粘贴到当前应用
    var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Keys.autoPaste) }
    }

    /// 暂停记录（比如要复制一些敏感内容时）
    var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Keys.isPaused) }
    }

    /// 呼出历史面板的快捷键
    var hotkey: HotkeyOption {
        didSet {
            defaults.set(hotkey.rawValue, forKey: Keys.hotkey)
            onHotkeyChanged?()
        }
    }

    /// 历史面板出现的位置
    var panelPlacement: PanelPlacement {
        didSet { defaults.set(panelPlacement.rawValue, forKey: Keys.panelPlacement) }
    }

    /// 不记录这些应用里复制的内容（保存的是应用的 Bundle ID，比如 "com.apple.Safari"）
    var ignoredBundleIDs: [String] {
        didSet { defaults.set(ignoredBundleIDs, forKey: Keys.ignoredBundleIDs) }
    }

    /// 快捷键改变时要做的事（由 AppModel 设置，用来重新注册快捷键）
    @ObservationIgnored var onHotkeyChanged: (() -> Void)?

    init() {
        // 第一次运行时使用的默认值
        defaults.register(defaults: [
            Keys.maxHistory: 200,
            Keys.autoPaste: true,
            Keys.isPaused: false,
            Keys.hotkey: HotkeyOption.cmdShiftV.rawValue,
            Keys.panelPlacement: PanelPlacement.nearMouse.rawValue,
            // 默认忽略"钥匙串访问"和"密码"应用
            Keys.ignoredBundleIDs: ["com.apple.keychainaccess", "com.apple.Passwords"],
        ])
        maxHistory = defaults.integer(forKey: Keys.maxHistory)
        autoPaste = defaults.bool(forKey: Keys.autoPaste)
        isPaused = defaults.bool(forKey: Keys.isPaused)
        hotkey = HotkeyOption(rawValue: defaults.string(forKey: Keys.hotkey) ?? "") ?? .cmdShiftV
        panelPlacement = PanelPlacement(rawValue: defaults.string(forKey: Keys.panelPlacement) ?? "") ?? .nearMouse
        ignoredBundleIDs = defaults.stringArray(forKey: Keys.ignoredBundleIDs) ?? []
    }

    private enum Keys {
        static let maxHistory = "maxHistory"
        static let autoPaste = "autoPaste"
        static let isPaused = "isPaused"
        static let hotkey = "hotkey"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let panelPlacement = "panelPlacement"
    }
}
