import SwiftUI

/// 点击菜单栏图标后弹出的菜单
struct MenuBarContentView: View {
    let app: AppModel

    /// 菜单里最多显示几条最近记录
    private let recentLimit = 10

    var body: some View {
        @Bindable var settings = app.settings

        // 自动检查发现了新版本：放在最上面提醒一下，点了打开设置里的"更新"
        if let release = app.updater.latestRelease {
            Button {
                app.showSettings(revealUpdates: true)
            } label: {
                Label("发现新版本 \(release.version)，点击更新…", systemImage: "arrow.down.circle")
            }
            Divider()
        }

        Button("打开剪贴板历史    \(settings.hotkey.display)") {
            app.showPanel()
        }

        Divider()

        let recent = Array(app.store.items.prefix(recentLimit))
        if recent.isEmpty {
            Text("暂无记录")
        } else {
            ForEach(recent) { item in
                Button {
                    app.paste(item)
                } label: {
                    Label(menuTitle(for: item), systemImage: iconName(for: item))
                }
            }
        }

        Divider()

        Toggle("暂停记录", isOn: $settings.isPaused)
        Button("清空历史（保留置顶）") {
            app.store.clearUnpinned()
        }
        Button("设置…") {
            app.showSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("退出 ClipKeeper") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// 菜单项文字太长会很难看，截断到 40 个字符
    private func menuTitle(for item: ClipItem) -> String {
        let title = item.title
        return title.count > 40 ? String(title.prefix(40)) + "…" : title
    }

    private func iconName(for item: ClipItem) -> String {
        if item.isPinned { return "pin.fill" }
        switch item.kind {
        case .text:  return "text.alignleft"
        case .image: return "photo"
        case .file:  return "doc"
        }
    }
}
