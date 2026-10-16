import AppKit

/// 从 ClipKeeper 里打开其他应用（访达、系统设置、浏览器）。
///
/// 为什么要专门写一个工具？
/// macOS 14 开始，应用之间切换前台变成了"协作式"的：当前在前台的应用必须主动 **让出** 前台，
/// 别的应用才能跳到最前面。我们打开设置窗口时 ClipKeeper 在前台，如果直接叫访达显示文件夹，
/// 访达会因为"抢不到前台"而出不来，甚至出现"没有任何应用在前台"的状态，用户点访达也打不开。
/// 所以打开别的应用前，先用 `yieldActivation` 把前台让给它，再明确要求它激活。
enum OpenHelper {
    private static let finderBundleID = "com.apple.finder"
    private static let systemSettingsBundleID = "com.apple.systempreferences"

    /// 在访达中打开一个文件夹（文件夹不存在时会先创建）
    static func openInFinder(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: finderBundleID) else {
            NSWorkspace.shared.open(folder)
            return
        }
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: finderBundleID)
        NSWorkspace.shared.open([folder], withApplicationAt: finderURL, configuration: activatingConfiguration()) { _, error in
            if let error { print("用访达打开文件夹失败：\(error)") }
        }
    }

    /// 打开"系统设置"里的某个页面
    static func openSystemSettings(_ url: URL) {
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: systemSettingsBundleID)
        NSWorkspace.shared.open(url, configuration: activatingConfiguration()) { _, error in
            if let error { print("打开系统设置失败：\(error)") }
        }
    }

    /// 用默认浏览器打开网页
    static func openWebPage(_ url: URL) {
        if let browserURL = NSWorkspace.shared.urlForApplication(toOpen: url),
           let browserID = Bundle(url: browserURL)?.bundleIdentifier {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: browserID)
        }
        NSWorkspace.shared.open(url, configuration: activatingConfiguration()) { _, error in
            if let error { print("打开网页失败：\(error)") }
        }
    }

    /// 打开后让目标应用跳到最前面
    private static func activatingConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return configuration
    }
}
