import SwiftUI

/// 应用入口。@main 表示程序从这里开始运行。
@main
struct ClipKeeperApp: App {
    /// 借助 AppDelegate，在应用启动完成后做初始化工作
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 菜单栏图标，以及点击后弹出的菜单
        MenuBarExtra {
            MenuBarContentView(app: AppModel.shared)
        } label: {
            // 回形针图标（Assets.xcassets 里的模板图片，系统会按菜单栏深浅自动着色）。
            // 暂停记录时换成右下角带暂停标记的版本，两张图宽度相同，切换时菜单栏不会跳动。
            Image(AppModel.shared.settings.isPaused ? "MenuBarIconPaused" : "MenuBarIcon")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 演示模式只是用来截图的临时实例，不要把正在使用的 ClipKeeper 关掉
        if !AppModel.isDemoMode {
            terminateOtherInstances()
        }
        AppModel.shared.start()
    }

    /// 同一时间只允许运行一个 ClipKeeper。
    ///
    /// 如果同时运行了两个（比如 Xcode 里运行的调试版 + 之前安装的版本），
    /// 它们会同时监听剪贴板、读写同一个数据库、抢同一个快捷键，导致各种奇怪的问题。
    /// 所以新启动的实例会让旧的实例退出，以最新启动的为准。
    private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        for app in others {
            app.terminate()
        }
    }
}
